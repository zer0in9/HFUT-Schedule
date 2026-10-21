import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif

enum CASPasswordCipher {
    /// Matches the upstream CAS AES/ECB/PKCS5Padding contract, always sent over HTTPS.
    static func encrypt(_ password: String, key: String) throws -> String {
        #if canImport(CommonCrypto)
        let input = Array(password.utf8), keyBytes = Array(key.utf8)
        guard [16, 24, 32].contains(keyBytes.count) else { throw AcademicError.invalidResponse("认证密钥") }
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                             CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
                             keyBytes, keyBytes.count, nil, input, input.count, &output, capacity, &written)
        guard status == kCCSuccess else { throw AcademicError.unavailable }
        return Data(output.prefix(written)).base64EncodedString()
        #else
        throw AcademicError.unavailable
        #endif
    }
}
