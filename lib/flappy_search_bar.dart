library flappy_search_bar;

import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'search_bar_style.dart';

mixin _ControllerListener<T> on State<SearchBar<T>> {
  void onListChanged(List<T> items) {}

  void onLoading() {}

  void onError(Error error) {}
}

class SearchBarController<T> {
  final List<T> _list = [];
  final List<T> _filteredList = [];
  final List<T> _sortedList = [];
  String _lastSearchedText;
  Future<List<T>> Function(String text) _lastSearchFunction;
  _ControllerListener _controllerListener;
  int Function(T a, T b) _lastSorting;
  CancelableOperation _cancelableOperation;

  void setListener(_ControllerListener _controllerListener) {
    this._controllerListener = _controllerListener;
  }

  void _search(String text, Future<List<T>> Function(String text) onSearch) async {
    _controllerListener?.onLoading();
    try {
      if (_cancelableOperation != null && (!_cancelableOperation.isCompleted || !_cancelableOperation.isCanceled)) {
        _cancelableOperation.cancel();
      }
      _cancelableOperation = CancelableOperation.fromFuture(
        onSearch(text),
        onCancel: () => {},
      );

      final List<T> items = await _cancelableOperation.value;
      _lastSearchFunction = onSearch;
      _lastSearchedText = text;
      _list.clear();
      _filteredList.clear();
      _sortedList.clear();
      _lastSorting = null;
      _list.addAll(items);
      _controllerListener?.onListChanged(_list);
    } catch (error) {
      _controllerListener?.onError(error);
    }
  }

  void replayLastSearch() {
    if (_lastSearchFunction != null && _lastSearchedText != null) {
      _search(_lastSearchedText, _lastSearchFunction);
    }
  }

  void removeFilter() {
    _filteredList.clear();
    if (_lastSorting == null) {
      _controllerListener?.onListChanged(_list);
    } else {
      _sortedList.clear();
      _sortedList.addAll(List<T>.from(_list));
      _sortedList.sort(_lastSorting);
      _controllerListener?.onListChanged(_sortedList);
    }
  }

  void removeSort() {
    _sortedList.clear();
    _lastSorting = null;
    _controllerListener?.onListChanged(_filteredList.isEmpty ? _list : _filteredList);
  }

  void sortList(int Function(T a, T b) sorting) {
    _lastSorting = sorting;
    _sortedList.clear();
    _sortedList.addAll(List<T>.from(_filteredList.isEmpty ? _list : _filteredList));
    _sortedList.sort(sorting);
    _controllerListener?.onListChanged(_sortedList);
  }

  void filterList(bool Function(T item) filter) {
    _filteredList.clear();
    _filteredList.addAll(_sortedList.isEmpty ? _list.where(filter).toList() : _sortedList.where(filter).toList());
    _controllerListener?.onListChanged(_filteredList);
  }
}

class SearchBar<T> extends StatefulWidget {
  final Future<List<T>> Function(String text) onSearch;
  final List<T> suggestions;
  final Widget Function(T item, int index) buildSuggestion;
  final int minimumChars;
  final Widget Function(T item, int index) onItemFound;
  final Widget Function(Error error) onError;
  final Duration debounceDuration;
  final Widget loader;
  final Widget emptyWidget;
  final Widget placeHolder;
  final Widget icon;
  final Widget header;
  final String hintText;
  final TextStyle hintStyle;
  final Color iconActiveColor;
  final TextStyle textStyle;
  final Text cancellationText;
  SearchBarController searchBarController;
  final SearchBarStyle searchBarStyle;
  final int crossAxisCount;
  final bool shrinkWrap;
  final IndexedStaggeredTileBuilder staggeredTileBuilder;
  final Axis scrollDirection;
  final double mainAxisSpacing;
  final double crossAxisSpacing;

  SearchBar({
    Key key,
    @required this.onSearch,
    @required this.onItemFound,
    this.searchBarController,
    this.minimumChars = 3,
    this.debounceDuration = const Duration(milliseconds: 500),
    this.loader = const Center(child: CircularProgressIndicator()),
    this.onError,
    this.emptyWidget = const SizedBox.shrink(),
    this.header,
    this.placeHolder,
    this.icon = const Icon(Icons.search),
    this.hintText = "",
    this.hintStyle = const TextStyle(color: Color.fromRGBO(142, 142, 147, 1)),
    this.iconActiveColor = Colors.black,
    this.textStyle = const TextStyle(color: Colors.black),
    this.cancellationText = const Text("Cancel"),
    this.suggestions = const [],
    this.buildSuggestion,
    this.searchBarStyle = const SearchBarStyle(),
    this.crossAxisCount = 1,
    this.shrinkWrap = false,
    this.staggeredTileBuilder,
    this.scrollDirection = Axis.vertical,
    this.mainAxisSpacing = 0.0,
    this.crossAxisSpacing = 0.0,
  }) : super(key: key);

  @override
  _SearchBarState createState() => _SearchBarState<T>();
}

class _SearchBarState<T> extends State<SearchBar<T>> with TickerProviderStateMixin, _ControllerListener<T> {
  bool _loading = false;
  Widget _error;
  final _searchQueryController = TextEditingController();
  Timer _debounce;
  bool _animate = false;
  List<T> _list = [];
  SearchBarController searchBarController;

  @override
  void initState() {
    super.initState();
    searchBarController = widget.searchBarController ?? SearchBarController<T>();
    searchBarController.setListener(this);
  }

  @override
  void onListChanged(List<T> items) {
    setState(() {
      _loading = false;
      _list = items;
    });
  }

  @override
  void onLoading() {
    setState(() {
      _loading = true;
      _error = null;
      _animate = true;
    });
  }

  @override
  void onError(Error error) {
    setState(() {
      _loading = false;
      _error = widget.onError != null ? widget.onError(error) : Text("error");
    });
  }

  _onTextChanged(String newText) async {
    if (_debounce?.isActive ?? false) {
      _debounce.cancel();
    }

    _debounce = Timer(widget.debounceDuration, () async {
      if (newText.length >= widget.minimumChars && widget.onSearch != null) {
        searchBarController._search(newText, widget.onSearch);
      } else {
        setState(() {
          _list.clear();
          _error = null;
          _loading = false;
          _animate = false;
        });
      }
    });
  }

  void _cancel() {
    setState(() {
      _searchQueryController.clear();
      _list.clear();
      _error = null;
      _loading = false;
      _animate = false;
    });
  }

  Widget _buildListView(List<T> items, Widget Function(T item, int index) builder) {
    return StaggeredGridView.countBuilder(
      crossAxisCount: widget.crossAxisCount,
      itemCount: items.length,
      shrinkWrap: widget.shrinkWrap,
      staggeredTileBuilder: widget.staggeredTileBuilder ?? (int index) => StaggeredTile.fit(1),
      scrollDirection: widget.scrollDirection,
      mainAxisSpacing: widget.mainAxisSpacing,
      crossAxisSpacing: widget.crossAxisSpacing,
      itemBuilder: (BuildContext context, int index) {
        return builder(items[index], index);
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_error != null) {
      return _error;
    } else if (_loading) {
      return widget.loader;
    } else if (_searchQueryController.text.length < widget.minimumChars) {
      if (widget.placeHolder != null) return widget.placeHolder;
      return _buildListView(widget.suggestions, widget.buildSuggestion ?? widget.onItemFound);
    } else if (_list.isNotEmpty) {
      return _buildListView(_list, widget.onItemFound);
    } else {
      return widget.emptyWidget;
    }
  }

  @override
  Widget build(BuildContext context) {
    final widthMax = MediaQuery.of(context).size.width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          height: 80,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  width: _animate ? widthMax * .8 : widthMax,
                  decoration: BoxDecoration(
                    borderRadius: widget.searchBarStyle.borderRadius,
                    color: widget.searchBarStyle.backgroundColor,
                  ),
                  child: Padding(
                    padding: widget.searchBarStyle.padding,
                    child: Theme(
                      child: TextField(
                        controller: _searchQueryController,
                        onChanged: _onTextChanged,
                        style: widget.textStyle,
                        decoration: InputDecoration(
                          icon: widget.icon,
                          border: InputBorder.none,
                          hintText: widget.hintText,
                          hintStyle: widget.hintStyle,
                        ),
                      ),
                      data: Theme.of(context).copyWith(
                        primaryColor: widget.iconActiveColor,
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _cancel,
                child: AnimatedOpacity(
                  opacity: _animate ? 1.0 : 0,
                  curve: Curves.easeIn,
                  duration: Duration(milliseconds: _animate ? 1000 : 0),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    width: _animate ? MediaQuery.of(context).size.width * .2 : 0,
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: widget.cancellationText,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        widget.header ?? Container(),
        Expanded(
          child: _buildContent(context),
        ),
      ],
    );
  }
}
