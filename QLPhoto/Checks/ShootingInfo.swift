import Foundation
import ImageIO

@main struct ShootingInfoCheck {
    static func main() {
        func info(_ exif: [String: Any]) -> [String: String] {
            Dictionary(uniqueKeysWithValues: ShootingInfo(properties: [kCGImagePropertyExifDictionary as String: exif]).primary)
        }
        let values = info([
            kCGImagePropertyExifISOSpeedRatings as String: [100],
            kCGImagePropertyExifExposureTime as String: 1.0 / 125,
            kCGImagePropertyExifFNumber as String: 1.8,
            kCGImagePropertyExifFocalLength as String: 6.86,
            kCGImagePropertyExifExposureBiasValue as String: -0.333,
            kCGImagePropertyExifFocalLenIn35mmFilm as String: 24
        ])
        precondition(values["ISO"] == "100")
        precondition(values["快门"] == "1/125 s")
        precondition(values["光圈"] == "ƒ/1.8")
        precondition(values["焦距"] == "6.86 mm")
        precondition(values["曝光补偿"] == "-0.33 EV")
        precondition(values["等效焦距"] == "24 mm")
        precondition(info([kCGImagePropertyExifExposureTime as String: 2.5])["快门"] == "2.5 s")
        precondition(info([kCGImagePropertyExifExposureBiasValue as String: 0])["曝光补偿"] == "0 EV")
        precondition(info([kCGImagePropertyExifExposureBiasValue as String: 1])["曝光补偿"] == "+1 EV")
        precondition(info([kCGImagePropertyExifExposureTime as String: 0])["快门"] == "未包含")
        precondition(info([kCGImagePropertyExifFNumber as String: Double.nan])["光圈"] == "未包含")
        precondition(info([:]).values.allSatisfy { $0 == "未包含" })
        print("PASS 拍摄参数：ISO、快门、光圈、焦距、曝光补偿、等效焦距、长曝光及缺失/非法数据")
    }
}
