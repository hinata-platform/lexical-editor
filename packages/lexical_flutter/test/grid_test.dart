import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

/// A box whose height changes without its parent rebuilding — what a cell
/// does when an image in it decodes.
class _Growing extends StatefulWidget {
  const _Growing({required this.height});

  final ValueNotifier<double> height;

  @override
  State<_Growing> createState() => _GrowingState();
}

class _GrowingState extends State<_Growing> {
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: widget.height,
    builder: (context, height, _) => SizedBox(height: height),
  );
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required ValueNotifier<double> height,
    GridColumnWidths? columnWidths,
  }) => tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LexicalGrid(
                columnCount: 2,
                columnWidths: columnWidths,
                children: [
                  GridCell(
                    placement: const GridPlacement(row: 0, column: 0),
                    child: _Growing(height: height),
                  ),
                  const GridCell(
                    placement: GridPlacement(row: 0, column: 1),
                    child: SizedBox(key: ValueKey('right'), height: 20),
                  ),
                ],
              ),
              const SizedBox(key: ValueKey('below'), height: 10),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('a cell that grows later grows its row and moves what follows', (
    tester,
  ) async {
    // A cell is laid out with its row's height. Laid out with *tight*
    // constraints it would be a relayout boundary, and a picture decoding in
    // it later would relayout the cell alone: the row kept its old height,
    // and the content ran over the blocks below it.
    final height = ValueNotifier<double>(10);
    await pump(tester, height: height);
    expect(tester.getTopLeft(find.byKey(const ValueKey('below'))).dy, 20);

    height.value = 150;
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('below'))).dy, 150);
    // The neighbour still reaches the bottom of the row.
    expect(tester.getSize(find.byKey(const ValueKey('right'))).height, 150);
  });

  testWidgets('nested grids lay a cell out a bounded number of times', (
    tester,
  ) async {
    // Three grids deep, each with a short cell that is stretched to its row.
    // Laying a stretched cell out twice per pass — once to measure, once to
    // stretch — doubles at every level: 2^depth layouts of the innermost
    // cell for one change at the top.
    final counter = [0];
    final tall = ValueNotifier<double>(500);
    Widget grid(Widget short, double height) => LexicalGrid(
      columnCount: 2,
      children: [
        GridCell(
          placement: const GridPlacement(row: 0, column: 0),
          child: short,
        ),
        GridCell(
          placement: const GridPlacement(row: 0, column: 1),
          child: SizedBox(height: height),
        ),
      ],
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            child: ValueListenableBuilder<double>(
              valueListenable: tall,
              builder: (context, height, _) => LexicalGrid(
                columnCount: 2,
                children: [
                  GridCell(
                    placement: const GridPlacement(row: 0, column: 0),
                    child: grid(
                      grid(
                        _Counting(
                          counter: counter,
                          child: const SizedBox(height: 10),
                        ),
                        300,
                      ),
                      400,
                    ),
                  ),
                  GridCell(
                    placement: const GridPlacement(row: 0, column: 1),
                    child: SizedBox(height: height),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(counter[0], lessThanOrEqualTo(2));

    counter[0] = 0;
    tall.value = 600;
    await tester.pump();
    expect(counter[0], lessThanOrEqualTo(2));
  });

  testWidgets('columns take the widths they are given', (tester) async {
    await pump(
      tester,
      height: ValueNotifier<double>(10),
      columnWidths: (available) => [available * 0.51, available * 0.49],
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('right'))).dx, 306);
  });

  testWidgets('a null width list stacks the cells', (tester) async {
    await pump(
      tester,
      height: ValueNotifier<double>(30),
      columnWidths: (_) => null,
    );
    final right = tester.getRect(find.byKey(const ValueKey('right')));
    expect(right.top, 30);
    expect(right.width, 600);
  });
}

/// Counts how often it is laid out.
class _Counting extends SingleChildRenderObjectWidget {
  const _Counting({required this.counter, super.child});

  final List<int> counter;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCounting(counter);
}

class _RenderCounting extends RenderProxyBox {
  _RenderCounting(this.counter);

  final List<int> counter;

  @override
  void performLayout() {
    counter[0]++;
    super.performLayout();
  }
}
