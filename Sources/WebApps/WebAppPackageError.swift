import Foundation

enum WebAppPackageError: LocalizedError {
    case unsupportedFile
    case packageTooLarge
    case invalidArchive
    case tooManyEntries
    case expandedSizeTooLarge
    case unsafePath(String)
    case symbolicLinksNotAllowed
    case nativeExecutableNotAllowed(String)
    case missingManifest
    case invalidManifest(String)
    case unsupportedSchema(Int)
    case unsupportedAppType(String)
    case invalidIdentifier
    case invalidVersion
    case missingEntry(String)
    case invalidEntry(String)
    case invalidIcon(String)
    case runtimeTooOld(required: String, current: String)
    case recordMissing
    case versionMissing(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return "الملف ليس حزمة 3E Web صالحة. استخدم ملفًا بامتداد .3eweb أو .zip."
        case .packageTooLarge:
            return "حجم الحزمة أكبر من الحد المسموح به."
        case .invalidArchive:
            return "تعذر قراءة ملف الحزمة كأرشيف ZIP صالح."
        case .tooManyEntries:
            return "الحزمة تحتوي على عدد ملفات أكبر من الحد المسموح به."
        case .expandedSizeTooLarge:
            return "الحجم المتوقع بعد فك الضغط أكبر من الحد المسموح به."
        case .unsafePath(let path):
            return "تحتوي الحزمة على مسار غير آمن: \(path)"
        case .symbolicLinksNotAllowed:
            return "الروابط الرمزية غير مسموحة داخل حزم التطبيقات."
        case .nativeExecutableNotAllowed(let name):
            return "تحتوي الحزمة على ملف تنفيذي أصلي غير مسموح: \(name)"
        case .missingManifest:
            return "لم يتم العثور على manifest.json في جذر الحزمة."
        case .invalidManifest(let details):
            return "ملف manifest.json غير صالح: \(details)"
        case .unsupportedSchema(let version):
            return "إصدار بنية الحزمة غير مدعوم: \(version)"
        case .unsupportedAppType(let type):
            return "نوع التطبيق غير مدعوم في هذه النسخة: \(type)"
        case .invalidIdentifier:
            return "معرّف التطبيق غير صالح. استخدم حروفًا وأرقامًا ونقاطًا وشرطات فقط."
        case .invalidVersion:
            return "رقم إصدار التطبيق غير صالح."
        case .missingEntry(let entry):
            return "ملف بداية التطبيق غير موجود: \(entry)"
        case .invalidEntry(let entry):
            return "مسار ملف البداية غير آمن أو غير مدعوم: \(entry)"
        case .invalidIcon(let icon):
            return "مسار أيقونة التطبيق غير آمن أو الملف غير موجود: \(icon)"
        case .runtimeTooOld(let required, let current):
            return "التطبيق يحتاج 3ELocal \(required) أو أحدث. الإصدار الحالي \(current)."
        case .recordMissing:
            return "سجل التطبيق المثبت غير موجود أو تالف."
        case .versionMissing(let version):
            return "ملفات الإصدار \(version) غير موجودة."
        }
    }
}
