library swipe_cards;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:swipe_cards/draggable_card.dart';
import 'package:swipe_cards/profile_card.dart';

class SwipeCards extends StatefulWidget {
  final IndexedWidgetBuilder itemBuilder;
  final Widget? likeTag;
  final Widget? nopeTag;
  final Widget? skipTag;
  final Widget? backTag;  // Add this line
  final MatchEngine matchEngine;
  final Function onStackFinished;
  final Function(SwipeItem, int)? itemChanged;
  final bool fillSpace;
  final bool upSwipeAllowed;
  final bool leftSwipeAllowed;
  final bool rightSwipeAllowed;
  final bool downSwipeAllowed; // Added for backward motion

  SwipeCards({
    Key? key,
    required this.matchEngine,
    required this.onStackFinished,
    required this.itemBuilder,
    this.likeTag,
    this.nopeTag,
    this.skipTag,
    this.backTag,  // Add this line
    this.fillSpace = true,
    this.upSwipeAllowed = false,
    this.leftSwipeAllowed = true,
    this.rightSwipeAllowed = true,
    this.downSwipeAllowed = false, // Default to true for backward motion
    this.itemChanged,
  }) : super(key: key);

  @override
  _SwipeCardsState createState() => _SwipeCardsState();
}

class _SwipeCardsState extends State<SwipeCards> {
  Key? _frontCard;
  SwipeItem? _currentItem;
  double _nextCardScale = 0.9;
  SlideRegion? slideRegion;

  @override
  void initState() {
    widget.matchEngine.addListener(_onMatchEngineChange);
    _currentItem = widget.matchEngine.currentItem;
    if (_currentItem != null) {
      _currentItem!.addListener(_onMatchChange);
    }
    int? currentItemIndex = widget.matchEngine._currentItemIndex;
    if (currentItemIndex != null) {
      _frontCard = Key(currentItemIndex.toString());
    }
    super.initState();
  }

  @override
  void dispose() {
    if (_currentItem != null) {
      _currentItem!.removeListener(_onMatchChange);
    }
    widget.matchEngine.removeListener(_onMatchEngineChange);
    super.dispose();
  }

  @override
  void didUpdateWidget(SwipeCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.matchEngine != oldWidget.matchEngine) {
      oldWidget.matchEngine.removeListener(_onMatchEngineChange);
      widget.matchEngine.addListener(_onMatchEngineChange);
    }
    if (_currentItem != null) {
      _currentItem!.removeListener(_onMatchChange);
    }
    _currentItem = widget.matchEngine.currentItem;
    if (_currentItem != null) {
      _currentItem!.addListener(_onMatchChange);
    }
  }

  void _onMatchEngineChange() {
    setState(() {
      if (_currentItem != null) {
        _currentItem!.removeListener(_onMatchChange);
      }
      _currentItem = widget.matchEngine.currentItem;
      if (_currentItem != null) {
        _currentItem!.addListener(_onMatchChange);
      }
      _frontCard = Key(widget.matchEngine._currentItemIndex.toString());
    });
  }

  void _onMatchChange() {
    setState(() {
      // match has been changed
    });
  }

  Widget _buildFrontCard() {
    return ProfileCard(
      child: widget.itemBuilder(context, widget.matchEngine._currentItemIndex!),
      key: _frontCard,
    );
  }

  Widget _buildBackCard() {
    return Transform(
      transform: Matrix4.identity()..scale(_nextCardScale, _nextCardScale),
      alignment: Alignment.center,
      child: ProfileCard(
        child: widget.itemBuilder(context, widget.matchEngine._nextItemIndex!),
      ),
    );
  }

  void _onSlideUpdate(double distance) {
    setState(() {
      _nextCardScale = 0.9 + (0.1 * (distance / 100.0)).clamp(0.0, 0.1);
    });
  }

  void _onSlideRegion(SlideRegion? region) {
    setState(() {
      slideRegion = region;
      SwipeItem? currentMatch = widget.matchEngine.currentItem;
      if (currentMatch != null && currentMatch.onSlideUpdate != null) {
        currentMatch.onSlideUpdate!(region);
      }
    });
  }

  void _onSlideOutComplete(SlideDirection? direction) {
    SwipeItem? currentMatch = widget.matchEngine.currentItem;
    switch (direction) {
      case SlideDirection.left:
        currentMatch?.nope();
        break;
      case SlideDirection.right:
        currentMatch?.like();
        break;
      case SlideDirection.up:
        currentMatch?.skip();
        break;
      case SlideDirection.down: // Added backward motion handling
        widget.matchEngine.rewindMatch(); // Bring back previous card
        break;
      case null:
        break;
    }

    if (widget.matchEngine._nextItemIndex! <
        widget.matchEngine._swipeItems!.length) {
      widget.itemChanged?.call(
          widget.matchEngine.nextItem!, widget.matchEngine._nextItemIndex!);
    }

    widget.matchEngine.cycleMatch();
    if (widget.matchEngine.currentItem == null) {
      widget.onStackFinished();
    }
  }

  SlideDirection? _desiredSlideOutDirection() {
    switch (widget.matchEngine.currentItem!.decision) {
      case Decision.nope:
        return SlideDirection.left;
      case Decision.like:
        return SlideDirection.right;
      case Decision.skip:
        return SlideDirection.up;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: widget.fillSpace == true ? StackFit.expand : StackFit.loose,
      children: <Widget>[
        if (widget.matchEngine.nextItem != null)
          DraggableCard(
            isDraggable: false,
            card: _buildBackCard(),
            upSwipeAllowed: widget.upSwipeAllowed,
            leftSwipeAllowed: widget.leftSwipeAllowed,
            rightSwipeAllowed: widget.rightSwipeAllowed,
            downSwipeAllowed: widget.downSwipeAllowed, // Allow backward motion
            isBackCard: true,
          ),
        if (widget.matchEngine.currentItem != null)
          DraggableCard(
            card: _buildFrontCard(),
            likeTag: widget.likeTag,
            nopeTag: widget.nopeTag,
            skipTag: widget.skipTag,
            backTag: widget.backTag,  // Add this line
            slideTo: _desiredSlideOutDirection(),
            onSlideUpdate: _onSlideUpdate,
            onSlideRegionUpdate: _onSlideRegion,
            onSlideOutComplete: _onSlideOutComplete,
            upSwipeAllowed: widget.upSwipeAllowed,
            leftSwipeAllowed: widget.leftSwipeAllowed,
            rightSwipeAllowed: widget.rightSwipeAllowed,
            downSwipeAllowed: widget.downSwipeAllowed, // Enable backward motion
            isBackCard: false,
          )
      ],
    );
  }
}

class MatchEngine extends ChangeNotifier {
  final List<SwipeItem>? _swipeItems;
  int? _currentItemIndex;
  int? _nextItemIndex;
  final List<int> _previousIndices = []; // To track swiped cards for rewind

  MatchEngine({
    List<SwipeItem>? swipeItems,
  }) : _swipeItems = swipeItems {
    _currentItemIndex = 0;
    _nextItemIndex = 1;
  }

  SwipeItem? get currentItem => _currentItemIndex! < _swipeItems!.length
      ? _swipeItems![_currentItemIndex!]
      : null;

  SwipeItem? get nextItem => _nextItemIndex! < _swipeItems!.length
      ? _swipeItems![_nextItemIndex!]
      : null;

  void cycleMatch() {
    if (currentItem!.decision != Decision.undecided) {
      currentItem!.resetMatch();
      _previousIndices.add(_currentItemIndex!); // Store current index for backward motion
      _currentItemIndex = _nextItemIndex;
      _nextItemIndex = _nextItemIndex! + 1;
      notifyListeners();
    }
  }

  void rewindMatch() {
    if (_previousIndices.isNotEmpty) {
      currentItem!.resetMatch();
      _nextItemIndex = _currentItemIndex;
      _currentItemIndex = _previousIndices.removeLast(); // Bring back the last swiped card
      currentItem!.resetMatch();
      notifyListeners();
    }
  }
}


class SwipeItem extends ChangeNotifier {
  final dynamic content;
  final Function? likeAction;
  final Function? skipAction;
  final Function? nopeAction;
  final Function? backAction;  // Add this line
  final Future Function(SlideRegion? slideRegion)? onSlideUpdate;
  Decision decision = Decision.undecided;

  SwipeItem({
    this.content,
    this.likeAction,
    this.skipAction,
    this.nopeAction,
    this.backAction,  // Add this line
    this.onSlideUpdate,
  });

  void back() {
    if (decision == Decision.undecided) {
      decision = Decision.back;  // You might need to add a 'back' option to your Decision enum
      try {
        backAction?.call();
      } catch (e) {}
      notifyListeners();
    }
  }

  void slideUpdateAction(SlideRegion? slideRegion) async {
    try {
      await onSlideUpdate!(slideRegion);
    } catch (e) {}
    notifyListeners();
  }

  void like() {
    if (decision == Decision.undecided) {
      decision = Decision.like;
      try {
        likeAction?.call();
      } catch (e) {}
      notifyListeners();
    }
  }

  void nope() {
    if (decision == Decision.undecided) {
      decision = Decision.nope;
      try {
        nopeAction?.call();
      } catch (e) {}
      notifyListeners();
    }
  }

  void skip() {
    if (decision == Decision.undecided) {
      decision = Decision.skip;
      try {
        skipAction?.call();
      } catch (e) {}
      notifyListeners();
    }
  }

  void resetMatch() {
    if (decision != Decision.undecided) {
      decision = Decision.undecided;
      notifyListeners();
    }
  }
}

enum Decision { undecided, nope, like, skip, back }
