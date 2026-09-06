import Foundation
import UIKit

enum ImageStorage {
    private static let folderName = "MealPhotos"

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Guarda la imagen en Documents/MealPhotos y devuelve el nombre del archivo.
    @discardableResult
    static func save(_ image: UIImage) throws -> String {
        let fileName = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "ImageStorage", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No se pudo codificar la imagen."])
        }
        try data.write(to: url(for: fileName), options: .atomic)
        return fileName
    }

    static func load(fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Redimensiona a máx. 1024 px de lado y comprime a JPEG ~0.7 para reducir tokens de la API.
    static func preparedForUpload(_ image: UIImage) -> Data? {
        image.resized(maxDimension: 1024).jpegData(compressionQuality: 0.7)
    }
}

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension, maxSide > 0 else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
