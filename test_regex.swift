import Foundation

let s = "1. **分类维度** — 你想按什么方式分？比如： **知识点**(如：导数、积分、向量、矩阵...)**错误类型**(如：计算错误、概念混淆、公式用错、审题失误...)**两者都要**(先按知识点分，再标注错误类型)"

var remaining = s

while !remaining.isEmpty {
    var bestRange: Range<String.Index>? = nil
    var bestKind = "plain"
    var bestInner = ""

    if let m = remaining.range(of: #"\*{2}(.+?)\*{2}"#, options: .regularExpression) {
        if bestRange == nil || m.lowerBound < bestRange!.lowerBound {
            bestRange = m
            bestKind = "bold"
            let matched = String(remaining[m])
            bestInner = String(matched.dropFirst(2).dropLast(2))
        }
    }
    
    guard let range = bestRange else {
        print("plain: \(remaining)")
        break
    }
    
    let pre = String(remaining[..<range.lowerBound])
    if !pre.isEmpty {
        print("plain: \(pre)")
    }
    print("\(bestKind): \(bestInner)")
    
    remaining = String(remaining[range.upperBound...])
}
