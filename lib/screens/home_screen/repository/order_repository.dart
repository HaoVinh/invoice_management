import 'dart:convert';

import '/repositories/abstract_repository.dart';
import '/screens/home_screen/model/order.dart';

import '../../../repositories/abstract_interface.dart';

class OrderRepository extends AbstractRepository
    implements AbstractInterface<double, Order> {
  final String orderUrl = "/storeDto";

  // Get all storeDto
  @override
  Future<List<Order>> getAll() async {
    try {
      final response = await get(url: orderUrl);
      return (response.data['data'] as List)
          .map((e) => Order.fromJson(e))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  // Get storeDto by id
  @override
  Future<Order> getOne(double id) async {
    try {
      final response = await get(url: "$orderUrl/$id");
      return Order.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  // Create storeDto
  @override
  Future<Order> create(Order storeDto) async {
    try {
      final response = await post(url: orderUrl, data: storeDto.toJson());
      return Order.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  // Update storeDto
  @override
  Future<Order> update(Order storeDto) async {
    try {
      final response = await put(
          url: "$orderUrl/${storeDto.id}", data: storeDto.toJson());
      return Order.fromJson(response.data);
    } catch (e) {
      rethrow;
    }
  }

  // Delete storeDto
  @override
  Future<void> delete(Order storeDto) async {
    try {
      await deleteHttp(url: "$orderUrl/${storeDto.id}");
    } catch (e) {
      rethrow;
    }
  }
}
