import Foundation
import CryptoKit

// Public inputs only: public key, appcast signature, and the final archive.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fputs("Usage: verify_eddsa <public-key> <signature> <archive>\n", stderr)
    exit(1)
}
do {
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
    guard publicKey.isValidSignature(signature, for: archive) else {
        fputs("EdDSA verification failed\n", stderr)
        exit(1)
    }
} catch {
    fputs("EdDSA verification failed: \(error)\n", stderr)
    exit(1)
}
