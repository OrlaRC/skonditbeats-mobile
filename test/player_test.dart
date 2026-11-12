import 'package:flutter_test/flutter_test.dart';
import 'package:skondit_beats_mobile/features/catalog/domain/beat.dart';
import 'package:skondit_beats_mobile/features/player/player_controller.dart';

Beat _beat(String id) => Beat(id: id, nombre: id, genero: 'Trap', bpm: 90, precio: 100);

void main() {
  final queue = [_beat('a'), _beat('b'), _beat('c')];

  test('siguiente y anterior avanzan por la lista', () {
    expect(beatInQueue(queue, 'a', 1)?.id, 'b');
    expect(beatInQueue(queue, 'c', -1)?.id, 'b');
  });

  test('la lista da la vuelta en los extremos', () {
    expect(beatInQueue(queue, 'c', 1)?.id, 'a');
    expect(beatInQueue(queue, 'a', -1)?.id, 'c');
  });

  test('no salta si no hay otro beat o el actual no está en la lista', () {
    expect(beatInQueue([_beat('a')], 'a', 1), isNull);
    expect(beatInQueue(const [], 'a', 1), isNull);
    expect(beatInQueue(queue, 'z', 1), isNull);
  });
}
