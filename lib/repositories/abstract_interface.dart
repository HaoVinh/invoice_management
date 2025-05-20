
abstract class AbstractInterface<K, E> {
  Future<List<E>> getAll();
  Future<E> getOne(K id);
  Future<E> create(E invoiceTempDto);
  Future<E> update(E invoiceTempDto);
  Future<void> delete(E invoiceTempDto);
}
