import Foundation
import CryptoKit
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let infoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: info["SUPublicEDKey"] as! String)!)
let s = String(decoding: data, as: UTF8.self)
let re = try NSRegularExpression(pattern: "edSignature: ([A-Za-z0-9+/=]+)\\nlength: ([0-9]+)")
guard let match = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), let sigRange = Range(match.range(at: 1), in: s), let sizeRange = Range(match.range(at: 2), in: s), let signature = Data(base64Encoded: String(s[sigRange])), let size = Int(s[sizeRange]), size <= data.count, key.isValidSignature(signature, for: data.prefix(size)) else { fatalError("Invalid feed signature") }
print("Signed feed verified")
