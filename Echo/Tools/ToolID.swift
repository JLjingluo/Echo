import Foundation

enum ToolID: String, CaseIterable, Sendable {
    case write_file, read_file, list_files, delete_file, move_file
    case text_ops, diff_text, run_js, web_fetch, web_search
    case table_to_csv, date_calc, unit_convert, make_qrcode, ocr_image

    var label: String {
        switch self {
        case .write_file: return "写文件"
        case .read_file: return "读文件"
        case .list_files: return "列文件"
        case .delete_file: return "删文件"
        case .move_file: return "移动/改名"
        case .text_ops: return "文本处理"
        case .diff_text: return "文本对比"
        case .run_js: return "跑 JS"
        case .web_fetch: return "抓网页"
        case .web_search: return "联网搜索"
        case .table_to_csv: return "表格转 CSV"
        case .date_calc: return "日期计算"
        case .unit_convert: return "单位换算"
        case .make_qrcode: return "生成二维码"
        case .ocr_image: return "图片识字"
        }
    }

    var icon: String {
        switch self {
        case .write_file: return "square.and.pencil"
        case .read_file: return "doc.text"
        case .list_files: return "folder"
        case .delete_file: return "trash"
        case .move_file: return "arrow.right.folder"
        case .text_ops: return "text.magnifyingglass"
        case .diff_text: return "rectangle.split.2x1"
        case .run_js: return "curlybraces"
        case .web_fetch: return "globe"
        case .web_search: return "magnifyingglass"
        case .table_to_csv: return "tablecells"
        case .date_calc: return "calendar"
        case .unit_convert: return "rulers"
        case .make_qrcode: return "qrcode"
        case .ocr_image: return "text.viewfinder"
        }
    }
}
