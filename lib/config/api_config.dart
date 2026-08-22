class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'https://sls-express.com/api/mobile';
  static const String login = '$baseUrl/users/login';
  static const String refreshAuth = '$baseUrl/users/refresh-auth';
  static const String tasks = '$baseUrl/tasks';
}
