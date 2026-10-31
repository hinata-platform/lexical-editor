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
