import '../models/page_model.dart';
import 'board_command.dart';

class HistoryManager {
  final int maxHistoryDepth;
  final List<BoardCommand> _undoStack = [];
  final List<BoardCommand> _redoStack = [];

  HistoryManager({this.maxHistoryDepth = 50});

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  String? get nextUndoDescription =>
      _undoStack.isNotEmpty ? _undoStack.last.description : null;
  String? get nextRedoDescription =>
      _redoStack.isNotEmpty ? _redoStack.last.description : null;

  PageModel execute(BoardCommand command, PageModel currentPage) {
    final newPage = command.apply(currentPage);
    _undoStack.add(command);
    if (_undoStack.length > maxHistoryDepth) {
      _undoStack.removeAt(0); // Evict oldest to keep memory bounded
    }
    _redoStack.clear(); // Any new action invalidates redo history
    return newPage;
  }

  /// Records a command whose effect has already been applied to the page
  /// (e.g. a live eraser or drag gesture). Clears redo like [execute].
  void push(BoardCommand command) {
    _undoStack.add(command);
    if (_undoStack.length > maxHistoryDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  PageModel undo(PageModel currentPage) {
    if (!canUndo) return currentPage;
    final command = _undoStack.removeLast();
    _redoStack.add(command);
    return command.undo(currentPage);
  }

  PageModel redo(PageModel currentPage) {
    if (!canRedo) return currentPage;
    final command = _redoStack.removeLast();
    _undoStack.add(command);
    return command.apply(currentPage);
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
