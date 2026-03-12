import Foundation

enum NetworkResult<T> {
    case success(T, statusCode: Int)
    case serverError(statusCode: Int, message: String)
    case networkError(Error)
    case unknownError(Error)
}
