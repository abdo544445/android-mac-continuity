import Foundation
import CryptoKit

public struct KeyPair: Sendable {
    public let privateKey: P256.KeyAgreement.PrivateKey
    public let publicKey: P256.KeyAgreement.PublicKey

    public var publicKeyBase64: String {
        publicKey.rawRepresentation.base64EncodedString()
    }

    public init() {
        let priv = P256.KeyAgreement.PrivateKey()
        self.privateKey = priv
        self.publicKey = priv.publicKey
    }
}

public final class CryptoManager: @unchecked Sendable {
    public static let shared = CryptoManager()

    public init() {}

    /// Generates a new ephemeral ECDH P-256 keypair
    public func generateKeyPair() -> KeyPair {
        KeyPair()
    }

    /// Derives an AES-256-GCM symmetric session key from local private key and remote public key with PIN salt
    public func deriveSessionKey(
        localPrivateKey: P256.KeyAgreement.PrivateKey,
        remotePublicKeyBase64: String,
        pin: String
    ) throws -> SymmetricKey {
        guard let remoteData = Data(base64Encoded: remotePublicKeyBase64),
              let remotePublicKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: remoteData) else {
            throw ContinuityCryptoError.invalidPublicKey
        }

        let sharedSecret = try localPrivateKey.sharedSecretFromKeyAgreement(with: remotePublicKey)
        let salt = SHA256.hash(data: Data(pin.utf8))
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(salt),
            sharedInfo: Data("continuity-v1-session-key".utf8),
            outputByteCount: 32
        )
        return derivedKey
    }

    /// Calculates HMAC-SHA256 authentication tag to confirm key derivation
    public func computeAuthTag(sessionKey: SymmetricKey, challenge: String) -> String {
        let tag = HMAC<SHA256>.authenticationCode(for: Data(challenge.utf8), using: sessionKey)
        return Data(tag).base64EncodedString()
    }

    /// Verifies HMAC-SHA256 authentication tag
    public func verifyAuthTag(sessionKey: SymmetricKey, challenge: String, expectedTagBase64: String) -> Bool {
        guard let expectedTag = Data(base64Encoded: expectedTagBase64) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(expectedTag, authenticating: Data(challenge.utf8), using: sessionKey)
    }

    /// Computes hex-encoded SHA-256 checksum of data
    public func sha256Hex(data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Generates random 6-digit PIN for pairing
    public func generatePairingPin() -> String {
        let pin = Int.random(in: 100000...999999)
        return String(pin)
    }

    /// Encrypts plaintext data using AES-256-GCM
    public func encrypt(data: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw ContinuityCryptoError.encryptionFailed
        }
        return combined
    }

    /// Decrypts AES-256-GCM ciphertext data
    public func decrypt(combinedData: Data, key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

public enum ContinuityCryptoError: Error, LocalizedError {
    case invalidPublicKey
    case derivationFailed
    case encryptionFailed
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey:
            return "Invalid remote public key representation"
        case .derivationFailed:
            return "Failed to derive shared secret or session key"
        case .encryptionFailed:
            return "AES-256-GCM encryption failed"
        case .decryptionFailed:
            return "AES-256-GCM decryption failed"
        }
    }
}
