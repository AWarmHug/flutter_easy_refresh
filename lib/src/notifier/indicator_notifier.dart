part of easyrefresh;

/// 指示器状态
enum IndicatorMode {
  /// 默认状态，不具备任何触发条件
  /// 此时[Header]或者[Footer]不显示
  /// 刷新完成后回归此状态
  inactive,

  /// 超出列表但未达到触发任务距离
  /// 此状态松开，列表复原
  drag,

  /// 超出列表并达到触发任务距离
  /// 此状态松开，列表触发任务
  armed,

  /// 超出列表并达到触发任务距离
  /// 此状态表示用户已经松开
  ready,

  /// 任务执行中
  /// 进行中，直到完成任务
  processing,

  /// 任务完成
  /// 任务结束，但整个过程并未完成
  /// 设置结束的动画，将在此状态后进行
  processed,

  /// 整个刷新过程完成
  /// 结束后，回到[inactive]
  done,
}

/// 指示通知器
abstract class IndicatorNotifier extends ChangeNotifier {
  /// 断续提供器
  /// 用户[clamping]动画
  final TickerProvider vsync;

  /// 触发偏移量
  final double triggerOffset;

  /// 用户触发通知器
  @protected
  final ValueNotifier<bool> userOffsetNotifier;

  /// 定住让列表不越界
  final bool clamping;

  /// 方向
  Axis? _axis;
  Axis? get axis => _axis;

  AxisDirection? _axisDirection;
  AxisDirection? get axisDirection => _axisDirection;

  /// 偏移量
  double _offset = 0;
  double get offset => _offset;

  /// 位置
  late ScrollMetrics _position;

  /// 状态
  IndicatorMode _mode = IndicatorMode.inactive;
  IndicatorMode get mode => _mode;

  /// 动画控制器
  /// [clamping]为true时，用到
  AnimationController? _clampingAnimationController;

  /// 弹性属性
  final SpringDescription? _spring;

  /// 滚动物理形式
  late ERScrollPhysics _physics;

  /// 列表越界范围
  double get overExtent {
    if (this._mode == IndicatorMode.ready || this.modeLocked) {
      return triggerOffset;
    }
    return 0;
  }

  /// 状态锁定
  bool get modeLocked =>
      _mode == IndicatorMode.processing || _mode == IndicatorMode.processed;

  /// 获取弹性属性
  SpringDescription get spring => _spring ?? _physics.spring;

  IndicatorNotifier({
    required this.triggerOffset,
    required this.clamping,
    required this.userOffsetNotifier,
    required this.vsync,
    SpringDescription? spring,
  }) : _spring = spring {
    _initClampingAnimation();
    this.userOffsetNotifier.addListener(_onUserOffset);
  }

  /// [clamping]动画监听器
  void _clampingTick();

  /// 计算偏移量
  double _calculateOffset(ScrollMetrics position, double value);

  @override
  void dispose() {
    super.dispose();
    _clampingAnimationController?.dispose();
    this.userOffsetNotifier.removeListener(_onUserOffset);
  }

  /// 初始化[clamping]动画控制器
  void _initClampingAnimation() {
    if (this.clamping) {
      _clampingAnimationController = AnimationController.unbounded(
        vsync: this.vsync,
      );
      _clampingAnimationController!.addListener(_clampingTick);
    }
  }

  /// 监听用户时间
  void _onUserOffset() {
    if (this.userOffsetNotifier.value) {
      // clamping
      // 取消动画，更新偏移量
      if (this.clamping && _clampingAnimationController!.isAnimating) {
        _clampingAnimationController!.stop(canceled: true);
      }
    }
  }

  /// 绑定物理形式
  void _bindPhysics(ERScrollPhysics physics) {
    _physics = physics;
  }

  /// 创建回弹模拟
  /// [clamping]使用
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity);

  /// 模拟器更新
  void _updateBySimulation(ScrollMetrics position, double velocity) {
    this._position = position;
    // 更新方向
    if (this._axis != position.axis && _axisDirection != position.axisDirection) {
      _axis = position.axis;
      _axisDirection = position.axisDirection;
    }
    // 更新释放时的偏移量
    this._updateOffset(position, position.pixels, true);
    // 如果为clamping，且offset大于0，则开始动画
    if (this.clamping && this._offset > 0 && !this.modeLocked) {
      final simulation = this.createBallisticSimulation(position, velocity);
      if (simulation != null) {
        _startClampingAnimation(simulation);
      }
    }
  }

  /// 更新偏移量
  void _updateOffset(ScrollMetrics position, double value, bool bySimulation) {
    // clamping
    // 在任务处理中，不做任何处理
    if (this.clamping && this.modeLocked) {
      return;
    }
    // clamping
    // 在释放情况下，且offset大于0，则由动画控制
    if (!this.userOffsetNotifier.value &&
        this.clamping &&
        this._offset > 0 &&
        !bySimulation) {
      return;
    }
    this._position = position;
    // 记录旧状态
    final oldOffset = this._offset;
    final oldMode = this._mode;
    // 更新偏移量
    this._offset = _calculateOffset(position, value);
    // 如果没有越界则不操作
    if (oldOffset == 0 && this._offset == 0) {
      return;
    }
    // 更新状态
    this._updateMode();
    // 是否需要通知
    if (oldOffset == this._offset && oldMode == this._mode) {
      return;
    }
    // 避免绘制过程中setState()
    if (bySimulation) {
      return;
    }
    notifyListeners();
  }

  /// 更新状态
  void _updateMode() {
    // 任务执行中和任务完成中不更新
    if (!this.modeLocked) {
      if (this._offset == 0) {
        this._mode = IndicatorMode.inactive;
      } else if (this._offset < this.triggerOffset) {
        this._mode = IndicatorMode.drag;
      } else if (this._offset == this.triggerOffset) {
        // 必须超过才能触发任务
        this._mode = this._mode != IndicatorMode.ready
            ? IndicatorMode.armed
            : IndicatorMode.processing;
      } else if (this._offset > this.triggerOffset) {
        // 如果是用户在滑动(未释放则不执行任务)
        this._mode = userOffsetNotifier.value
            ? IndicatorMode.armed
            : IndicatorMode.ready;
      }
    }
  }

  /// 开始[clamping]动画
  void _startClampingAnimation(Simulation simulation) {
    if (this._offset <= 0) {
      return;
    }
    _clampingAnimationController!.animateWith(simulation);
  }

  /// 设置状态
  void setMode(IndicatorMode mode) {
    if (this._mode == mode) {
      return;
    }
    final oldMode = this._mode;
    this._mode = mode;
    notifyListeners();
    if (oldMode == IndicatorMode.processing &&
        _position is ScrollActivityDelegate) {
      (_position as ScrollActivityDelegate).goBallistic(0);
    }
  }
}

/// Header通知器
class HeaderNotifier extends IndicatorNotifier {
  HeaderNotifier({
    required double triggerOffset,
    required bool clamping,
    required ValueNotifier<bool> userOffsetNotifier,
    required TickerProvider vsync,
    SpringDescription? spring,
  }) : super(
          triggerOffset: triggerOffset,
          clamping: clamping,
          userOffsetNotifier: userOffsetNotifier,
          vsync: vsync,
          spring: spring,
        );

  @override
  double _calculateOffset(ScrollMetrics position, double value) {
    if (value >= position.minScrollExtent &&
        _offset != 0 &&
        !(this.clamping && this._offset > 0)) {
      return 0;
    }
    if (this.clamping) {
      if (value > position.minScrollExtent) {
        // 回收先减去偏移量
        return math.max(this._offset > 0 ? (-value + this._offset) : 0, 0);
      } else {
        // 越界累加偏移量
        return -value + this._offset;
      }
    } else {
      return value > position.minScrollExtent ? 0 : -value;
    }
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (this.clamping && this._offset > 0) {
      return BouncingScrollSimulation(
        spring: spring,
        position: position.pixels - this._offset,
        velocity: velocity,
        leadingExtent: position.minScrollExtent - this.overExtent,
        trailingExtent: 0,
        tolerance: _physics.tolerance,
      );
    }
    return null;
  }

  @override
  void _clampingTick() {
    this._offset = math.max(-_clampingAnimationController!.value, 0);
    this._updateMode();
    notifyListeners();
  }
}

/// Footer通知器
class FooterNotifier extends IndicatorNotifier {
  FooterNotifier({
    required double triggerOffset,
    required bool clamping,
    required ValueNotifier<bool> userOffsetNotifier,
    required TickerProvider vsync,
    SpringDescription? spring,
  }) : super(
          triggerOffset: triggerOffset,
          clamping: clamping,
          userOffsetNotifier: userOffsetNotifier,
          vsync: vsync,
          spring: spring,
        );

  @override
  double _calculateOffset(ScrollMetrics position, double value) {
    if (value <= position.maxScrollExtent &&
        _offset != 0 &&
        !(this.clamping && this._offset > 0)) {
      return 0;
    }
    // 移动量
    final move = value - position.maxScrollExtent;
    if (this.clamping) {
      if (value < position.maxScrollExtent) {
        // 回收先减去偏移量
        return math.max(this._offset > 0 ? (move + this._offset) : 0, 0);
      } else {
        // 越界累加偏移量
        return move + this._offset;
      }
    } else {
      return value < position.maxScrollExtent ? 0 : move;
    }
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    if (this.clamping && this._offset > 0) {
      return BouncingScrollSimulation(
        spring: spring,
        position: position.pixels + this._offset,
        velocity: velocity,
        leadingExtent: 0,
        trailingExtent: position.maxScrollExtent + this.overExtent,
        tolerance: _physics.tolerance,
      );
    }
    return null;
  }

  @override
  void _clampingTick() {
    this._offset = math.max(
        _clampingAnimationController!.value - _position.maxScrollExtent, 0);
    this._updateMode();
    notifyListeners();
  }
}
