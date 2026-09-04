import 'package:dio/dio.dart';

import '../../models/client.dart';
import '../../models/employee.dart';
import '../../models/interaction.dart';
import '../../models/reminder.dart';
import '../../models/sale.dart';
import 'api_client.dart';
import 'endpoints.dart';

class ApiService {
  ApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _client.post(
      Endpoints.login,
      data: {'username': username, 'password': password},
      requireAuth: false,
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> logout(String refreshToken, String accessToken) async {
    try {
      await _client.post(
        Endpoints.logout,
        data: {'refresh': refreshToken},
      );
    } catch (_) {}
  }

  Future<List<Employee>> getEmployees() async {
    final response = await _client.get(Endpoints.employees);
    return (response.data as List)
        .map((e) => Employee.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Employee> getEmployee(int id) async {
    final response = await _client.get(Endpoints.employeeDetail(id));
    return Employee.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Client>> getEmployeeClients(int id) async {
    final response = await _client.get(Endpoints.employeeClients(id));
    return (response.data as List)
        .map((e) => Client.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Sale>> getEmployeeSales(int id) async {
    final response = await _client.get(Endpoints.employeeSales(id));
    return (response.data as List)
        .map((e) => Sale.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<EmployeeDropdown>> getEmployeesDropdown() async {
    final response = await _client.get(Endpoints.employeesDropdown);
    return (response.data as List)
        .map((e) => EmployeeDropdown.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Employee> createEmployee(FormData formData) async {
    final response = await _client.upload(Endpoints.employees, formData);
    return Employee.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Employee> updateEmployee(int id, FormData formData) async {
    final response =
        await _client.upload(Endpoints.employeeUpdate(id), formData, method: 'PUT');
    return Employee.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteEmployee(int id) async {
    await _client.delete(Endpoints.employeeDelete(id));
  }

  Future<List<Sale>> getSales() async {
    final response = await _client.get(Endpoints.sales);
    return (response.data as List)
        .map((e) => Sale.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Sale> createSale(Map<String, dynamic> data) async {
    final response = await _client.post(Endpoints.createSale, data: data);
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Sale> updateSale(int id, Map<String, dynamic> data) async {
    final response = await _client.put(Endpoints.updateSale(id), data: data);
    return Sale.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteSale(int id) async {
    await _client.delete(Endpoints.deleteSale(id));
  }

  Future<List<Interaction>> getInteractions() async {
    final response = await _client.get(Endpoints.interactions);
    return (response.data as List)
        .map((e) => Interaction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Interaction> createInteraction(Map<String, dynamic> data) async {
    final response = await _client.post(Endpoints.createInteraction, data: data);
    return Interaction.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Interaction> updateInteraction(int id, Map<String, dynamic> data) async {
    final response = await _client.put(Endpoints.updateInteraction(id), data: data);
    return Interaction.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteInteraction(int id) async {
    await _client.delete(Endpoints.deleteInteraction(id));
  }

  Future<List<Reminder>> getReminders() async {
    final response = await _client.get(Endpoints.reminders);
    return (response.data as List)
        .map((e) => Reminder.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Reminder> createReminder(Map<String, dynamic> data) async {
    final response = await _client.post(Endpoints.createReminder, data: data);
    return Reminder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Reminder> updateReminder(int id, Map<String, dynamic> data) async {
    final response = await _client.put(Endpoints.updateReminder(id), data: data);
    return Reminder.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteReminder(int id) async {
    await _client.delete(Endpoints.deleteReminder(id));
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _client.post(
      Endpoints.changePassword,
      data: {
        'old_password': oldPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<void> importSales(FormData formData) async {
    await _client.upload(Endpoints.importSales, formData);
  }

  Future<void> importInteractions(FormData formData) async {
    await _client.upload(Endpoints.importInteractions, formData);
  }
}
