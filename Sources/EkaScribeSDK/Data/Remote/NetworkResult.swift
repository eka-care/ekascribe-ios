import Foundation

enum NetworkResult<T> {
    case success(T, statusCode: Int)
    case serverError(statusCode: Int, message: String, errorCode: String? = nil)
    case networkError(Error)
    case unknownError(Error)
}
