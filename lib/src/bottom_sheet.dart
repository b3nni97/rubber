import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:rubber/src/animation_controller.dart';

import 'package:after_layout/after_layout.dart';

import '../rubber.dart';

const double _kMinFlingVelocity = 700.0;
const double _kCompleteFlingVelocity = 5000.0;

class RubberBottomSheet extends StatefulWidget {
  const RubberBottomSheet(
      {Key? key,
      required this.animationController,
      required this.lowerLayer,
      required this.upperLayer,
      this.menuLayer,
      this.scrollController,
      this.header,
      this.headerHeight = 50.0,
      this.dragFriction = 0.52,
      this.onDragStart,
      this.onDragEnd,
      this.onTap,
      this.decoration})
      : super(key: key);

  final ScrollController? scrollController;
  final Widget lowerLayer;
  final Widget upperLayer;
  final Widget? menuLayer;

  /// Friction to apply when the sheet reaches its bounds.
  /// The higher the number, the more friction is applied.
  /// Defaults to 0.52.
  ///
  /// Warning: If `dragFriction < 0`, your bottom sheet will accelerate off the screen.
  final double dragFriction;
  final Function? onTap;

  /// Called when the user stops scrolling, if this function returns a false the bottomsheet
  /// won't complete the next onDragEnd instructions
  final Function()? onDragEnd;

  /// Called when the user stops scrolling, if this function returns a false the bottomsheet
  /// won't complete the next onDragEnd instructions
  final Function()? onDragStart;

  /// The widget on top of the rest of the bottom sheet.
  /// Usually used to make a non-scrollable area
  final Widget? header;
  // Parameter to change the header height, it's the only way to set the header height
  final double headerHeight;

  /// Instance of [RubberAnimationController] that controls the bottom sheet
  /// animation state
  final RubberAnimationController animationController;

  final BoxDecoration? decoration;

  static RubberBottomSheetState? of(BuildContext context,
      {bool nullOk = false}) {
    final RubberBottomSheetState? result =
        context.findAncestorStateOfType<RubberBottomSheetState>();
    if (nullOk || result != null) return result;
    throw FlutterError(
        'RubberBottomSheet.of() called with a context that does not contain a RubberBottomSheet.\n'
        'No RubberBottomSheet ancestor could be found starting from the context that was passed to RubberBottomSheet.of(). '
        '  $context');
  }

  @override
  RubberBottomSheetState createState() => RubberBottomSheetState();
}

class RubberBottomSheetState extends State<RubberBottomSheet>
    with TickerProviderStateMixin, AfterLayoutMixin<RubberBottomSheet> {
  late double _screenHeight;

  final GlobalKey _keyPeak = GlobalKey();
  final GlobalKey _keyWidget = GlobalKey(debugLabel: 'bottomsheet menu key');

  double get _bottomSheetHeight {
    final RenderBox renderBox =
        _keyWidget.currentContext!.findRenderObject() as RenderBox;
    return renderBox.size.height;
  }

  RubberAnimationController get controller => widget.animationController;

  bool get halfState => controller.halfBound != null;

  bool get _shouldScroll =>
      _scrollController != null &&
      _scrollController!.hasClients &&
      (controller.value >=
          (controller.upperBound ?? 1) -
              0.06); //Subtract 0.06 to prevent simulation from causing bottom sheet drags
  bool _scrolling = false;

  bool get _hasHeader => widget.header != null;

  /// Adding [substituteScrollController] a value the bottomsheet will change the default one
  ScrollController? substituteScrollController;
  ScrollController? get _scrollController =>
      substituteScrollController ?? widget.scrollController;

  /// If set true the drag won't move the bottomsheet but the scrolling will be always active
  bool _forceScrolling = false;
  forceScroll(bool force) {
    _forceScrolling = force;
    setScrolling(force);
  }

  bool _enabled = true;
  set enable(value) {
    _enabled = value;
  }

  @override
  void initState() {
    super.initState();
    controller.visibility.addListener(_visibilityListener);
  }

  @override
  void dispose() {
    controller.visibility.removeListener(_visibilityListener);
    controller.dispose();
    super.dispose();
  }

  bool _display = true;
  void _visibilityListener() {
    setState(() {
      _display = controller.visibility.value;
    });
  }

  Widget _buildSlideAnimation(BuildContext context, Widget? child) {
    var layout;
    if (widget.menuLayer != null) {
      layout = Stack(
        children: <Widget>[
          Align(
              alignment: Alignment.bottomLeft,
              child: _buildAnimatedBottomsheetWidget(context, child)),
          Align(alignment: Alignment.bottomLeft, child: widget.menuLayer),
        ],
      );
    } else {
      layout = _buildAnimatedBottomsheetWidget(context, child);
    }
    return GestureDetector(
      onTap: widget.onTap as void Function()?,
      onVerticalDragDown: _onVerticalDragDown,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      onVerticalDragCancel: _handleDragCancel,
      onVerticalDragStart: _handleDragStart,
      child: layout,
    );
  }

  Widget _buildAnimatedBottomsheetWidget(BuildContext context, Widget? child) {
    return FractionallySizedBox(
        alignment: Alignment.bottomCenter,
        heightFactor: widget.animationController.value,
        child: child);
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    _screenHeight = screenSize.height;
    var peak = Container(
      key: _keyPeak,
      height: widget.headerHeight,
      child: widget.header,
    );
    var bottomSheet = Container(
      decoration: widget.decoration,
      child: Stack(
        children: <Widget>[
          peak,
          Container(
              margin: EdgeInsets.only(
                  top: widget.header != null ? widget.headerHeight : 0),
              child: widget.upperLayer)
        ],
      ),
    );
    var elem;
    if (_display) {
      elem = AnimatedBuilder(
        animation: controller,
        builder: _buildSlideAnimation,
        child: bottomSheet,
      );
    } else {
      elem = Container();
    }
    return Stack(
      key: _keyWidget,
      children: <Widget>[
        widget.lowerLayer,
        Align(child: elem, alignment: Alignment.bottomRight),
      ],
    );
  }

  // Touch gestures
  Drag? _drag;
  ScrollHoldController? _hold;

  void _onVerticalDragDown(DragDownDetails details) {
    if (_enabled) {
      if (_hasHeader) {
        if (_draggingPeak(details.globalPosition)) {
          setScrolling(false);
        } else {
          setScrolling(true);
        }
      }
      if (_shouldScroll) {
        assert(_hold == null);
        _hold = _scrollController!.position.hold(_disposeHold);
      }
    }
  }

  Offset? _lastPosition;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_enabled) {
      _lastPosition = details.globalPosition;
      print("UPPER: " + controller.upperBound!.toString());
      print("SHOULD SCROLL: " + _shouldScroll.toString());
      if (_scrolling && _shouldScroll) {
        // _drag might be null if the drag activity ended and called _disposeDrag.
        assert(_hold == null || _drag == null);
        _drag?.update(details);
        if (_scrollController!.position.pixels <= 0 &&
            details.primaryDelta! > 0 &&
            !_forceScrolling) {
          setScrolling(false);
          _handleDragCancel();
          if (_scrollController!.position.pixels != 0.0) {
            _scrollController!.position.setPixels(0.0);
          }
        }
      } else {
        var friction = 1.0;
        var diff;
        // Friction if more than upper
        if (controller.value > controller.upperBound!) {
          diff = controller.value - controller.upperBound!;
        }
        // Friction if less than lower
        else if (controller.value < controller.lowerBound!) {
          diff = controller.lowerBound! - controller.value;
        }
        if (controller.value < controller.upperBound! &&
            controller.dismissable &&
            controller.animationState.value == AnimationState.expanded) {
          diff = controller.upperBound! - controller.value;
        }
        if (diff != null) {
          friction = 1 + (widget.dragFriction * pow(1 - diff, 2));
        }

        controller.value -= details.primaryDelta! / _screenHeight / friction;
        print("CONTROLLER VALUE 1: " + controller.value.toString());
        if (_shouldScroll &&
            controller.value >= controller.upperBound! &&
            !_draggingPeak(_lastPosition)) {
          controller.value = controller.upperBound!;
          print("CONTROLLER VALUE 2: " + controller.value.toString());
          setScrolling(true);
          var startDetails = DragStartDetails(
              sourceTimeStamp: details.sourceTimeStamp,
              globalPosition: details.globalPosition);
          _hold = _scrollController!.position.hold(_disposeHold);
          _drag = _scrollController!.position.drag(startDetails, _disposeDrag);
        } else {
          _handleDragCancel();
        }
      }
    }
  }

  setScrolling(bool scroll, {bool force = false}) {
    print("SET SCROLLING: " + scroll.toString());
    print("SHOULD SCROLL: " + _shouldScroll.toString());

    print(controller.value >= (controller.upperBound ?? 1));

    print("CONTROLLER: " + controller.value.toString());
    if (_shouldScroll || force) {
      _scrolling = scroll;
    }

    print("_scrolling: " + _scrolling.toString());
  }

  void _handleDragStart(DragStartDetails details) {
    if (_enabled) {
      if (widget.onDragStart != null) widget.onDragStart!();
      if (_shouldScroll) {
        // It's possible for _hold to become null between _handleDragDown and
        // _handleDragStart, for example if some user code calls jumpTo or otherwise
        // triggers a new activity to begin.
        assert(_drag == null);
        _drag = _scrollController!.position.drag(details, _disposeDrag);
        assert(_drag != null);
        assert(_hold == null);
      }
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_enabled) {
      // If onDragEnd returns a false value the method interrupts
      if (widget.onDragEnd != null) {
        var res = widget.onDragEnd!();
        if (res != null && !res) return;
      }

      final double flingVelocity =
          -details.velocity.pixelsPerSecond.dy / _screenHeight;
      if (_scrolling) {
        assert(_hold == null || _drag == null);
        _drag?.end(details);
        assert(_drag == null);
      } else {
        if (details.velocity.pixelsPerSecond.dy.abs() >
            _kCompleteFlingVelocity) {
          print("FLING 1");
          controller.fling(controller.lowerBound, controller.upperBound,
              velocity: flingVelocity);
        } else {
          if (halfState) {
            if (details.velocity.pixelsPerSecond.dy.abs() >
                _kMinFlingVelocity) {
              if (controller.value > controller.halfBound!) {
                print("FLING 2");
                controller.fling(controller.halfBound, controller.upperBound,
                    velocity: flingVelocity);
              } else {
                print("FLING 3");
                controller.fling(controller.lowerBound, controller.halfBound,
                    velocity: flingVelocity);
              }
            } else {
              if (controller.value >
                  (controller.upperBound! + controller.halfBound!) / 2) {
                print("EXPAND 1");
                controller.expand();
              } else if (controller.value >
                  (controller.halfBound! + controller.lowerBound!) / 2) {
                print("HALF EXPAND 1");
                controller.halfExpand();
              } else {
                print("COLLAPSE 1");
                controller.collapse();
              }
            }
          } else {
            if (details.velocity.pixelsPerSecond.dy.abs() >
                _kMinFlingVelocity) {
              print("FLING 4");
              controller.fling(controller.lowerBound, controller.upperBound,
                  velocity: flingVelocity);
            } else {
              if (controller.value >
                  (controller.upperBound! + controller.lowerBound!) / 2) {
                print("EXPAND 2");
                controller.expand();
              } else {
                print("COLLAPSE 2");
                controller.collapse();
              }
            }
          }
        }
      }
    }
  }

  void _handleDragCancel() {
    // _hold might be null if the drag started.
    // _drag might be null if the drag activity ended and called _disposeDrag.
    assert(_hold == null || _drag == null);
    _hold?.cancel();
    _drag?.cancel();
    assert(_hold == null);
    assert(_drag == null);
  }

  void _disposeHold() {
    _hold = null;
  }

  void _disposeDrag() {
    _drag = null;
  }

  @override
  void afterFirstLayout(BuildContext context) {
    setState(() {
      controller.height = _bottomSheetHeight;
    });
  }

  bool _draggingPeak(Offset? globalPosition) {
    if (!_hasHeader) return false;
    final RenderBox renderBoxRed =
        _keyPeak.currentContext!.findRenderObject() as RenderBox;
    final positionPeak = renderBoxRed.localToGlobal(Offset.zero);
    final sizePeak = renderBoxRed.size;
    final top = (sizePeak.height + positionPeak.dy);
    print('GLOBAL DY');
    print(globalPosition!.dy);
    print('TOP');
    print(top);
    print(globalPosition!.dy < top);
    return (globalPosition!.dy < top);
  }
}
