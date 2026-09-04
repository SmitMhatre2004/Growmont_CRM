class Endpoints {
  static const login = '/api/auth/login/';
  static const logout = '/api/auth/logout/';
  static const refresh = '/api/auth/refresh/';
  static const me = '/api/me/';
  static const changePassword = '/api/auth/password/change/';
  static const forgotPassword = '/api/auth/password/forgot/';

  static const employees = '/api/employees/';
  static String employeeDetail(int id) => '/api/employees/$id/';
  static String employeeUpdate(int id) => '/api/employees/$id/update/';
  static String employeeDelete(int id) => '/api/employees/$id/delete/';
  static String employeeClients(int id) => '/api/employees/$id/clients/';
  static String employeeSales(int id) => '/api/employees/$id/sales/';
  static const employeesDropdown = '/api/employees/dropdown/';

  static const sales = '/api/sales/';
  static const createSale = '/api/sales/create/';
  static String updateSale(int id) => '/api/sales/$id/update/';
  static String deleteSale(int id) => '/api/sales/$id/delete/';

  static const interactions = '/api/interactions/';
  static const createInteraction = '/api/interactions/create/';
  static String updateInteraction(int id) => '/api/interactions/$id/update/';
  static String deleteInteraction(int id) => '/api/interactions/$id/delete/';

  static const reminders = '/api/reminders/';
  static const createReminder = '/api/reminders/create/';
  static String updateReminder(int id) => '/api/reminders/$id/update/';
  static String deleteReminder(int id) => '/api/reminders/$id/delete/';

  static const exportSales = '/api/export/sales/';
  static const exportSalesFiltered = '/api/export/sales/filtered/';
  static const exportInteractions = '/api/export/interactions/';
  static const exportInteractionsFiltered = '/api/export/interactions/filtered/';

  static const importSales = '/api/import/sales/';
  static const importInteractions = '/api/import/interactions/';

  static const health = '/api/health/';
}
