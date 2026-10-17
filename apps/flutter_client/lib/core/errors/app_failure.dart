sealed class AppFailure implements Exception {
  const AppFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message);
}

class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure([super.message = '登录已过期，请重新登录']);
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {this.statusCode});
  final int? statusCode;
}

class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message);
}

class ServerFailure extends AppFailure {
  const ServerFailure(super.message);
}

class OfflineFailure extends AppFailure {
  const OfflineFailure([super.message = '无法连接服务器，请检查网络后重试']);
}

class ResponseFailure extends AppFailure {
  const ResponseFailure([super.message = '服务器返回的数据格式不正确']);
}
