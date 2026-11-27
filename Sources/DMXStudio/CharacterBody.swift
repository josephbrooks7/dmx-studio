import Foundation

// MARK: - Character body parameters (Phase 1: anatomical foundation)
//
// The body a performer has, kept separate from clothing, hair and rendering. Measurements are
// predicted from height and weight using statistics learned from ANSUR II (ansur2-model.json),
// blended by `correlationStrength`, shifted by the character's own `variation` (in standard
// deviations, so "long arms" stays long at any height) and replaced outright by any
// `manualOverrides`. Older saved performers have no body (nil) and keep working unchanged.

struct BodyComposition: Codable, Hashable {
    /// 0...1 normalized controls (not measured percentages)
    var muscleDevelopment: Double = 0.45
    var muscleDefinition: Double = 0.35
    var bodyFat: Double = 0.3
    /// regional fat and muscle, keyed by region name (e.g. "abdomen", "hips", "deltoids")
    var regionalFat: [String: Double] = [:]
    var regionalMuscle: [String: Double] = [:]
}

struct CharacterBody: Codable, Hashable {
    static let currentSchema = 1
    var schemaVersion: Int = CharacterBody.currentSchema
    /// "male" or "female": sets the starting statistics only, never limits what can be changed
    var baseModel: String = "male"
    var heightCm: Double = 175
    /// nil = use the population weight for this height
    var weightKg: Double? = nil
    /// 0 = measurements ignore height/weight, 1 = fully follow the statistics
    var correlationStrength: Double = 0.75
    /// individual variation in standard deviations per measurement (e.g. "armSpanCm": 1.5)
    var variation: [String: Double] = [:]
    /// exact values set by the user, in the measurement's own units (cm); always win
    var manualOverrides: [String: Double] = [:]
    var composition = BodyComposition()
    /// anatomy morph controls, 0...1, keyed by name (e.g. "abdominalDefinition", "buttockProjection")
    var anatomy: [String: Double] = [:]
}

extension PerformerAppearance {
    /// The body to use: the saved one, or a default derived from the legacy height/body style.
    var resolvedBody: CharacterBody {
        if let b = body { return b }
        var b = CharacterBody()
        b.baseModel = (bodyStyle == "Feminine") ? "female" : "male"
        b.heightCm = height * 100
        return b
    }
}

// MARK: - Measurement engine

struct BodyMeasurement: Hashable {
    enum Source: String { case override, predicted, population }
    var name: String
    var value: Double        // cm (kg for weight)
    var source: Source
    var conditionalSD: Double
}

final class AnthropometryModel {
    struct Stat { var mean: Double; var sd: Double; var p5: Double; var p50: Double; var p95: Double }
    struct Fit { var slope: Double; var intercept: Double; var residualSD: Double; var r: Double }
    struct Sex {
        var stats: [String: Stat] = [:]
        var vsStature: [String: Fit] = [:]
        var corrOrder: [String] = []
        var corr: [[Double]] = []
        func r(_ a: String, _ b: String) -> Double? {
            guard let i = corrOrder.firstIndex(of: a), let j = corrOrder.firstIndex(of: b) else { return nil }
            return corr[i][j]
        }
    }

    /// Character-facing measurement names and the ANSUR II columns they come from (ANSUR lengths are mm).
    static let columns: [String: String] = [
        "shoulderWidthCm": "biacromialbreadth", "outerShoulderWidthCm": "bideltoidbreadth",
        "neckCircumferenceCm": "neckcircumference", "neckBaseCircumferenceCm": "neckcircumferencebase",
        "chestCircumferenceCm": "chestcircumference", "waistCircumferenceCm": "waistcircumference",
        "hipCircumferenceCm": "buttockcircumference", "upperArmLengthCm": "acromionradialelength",
        "forearmLengthCm": "radialestylionlength", "handLengthCm": "handlength", "handWidthCm": "handbreadth",
        "inseamCm": "crotchheight", "footLengthCm": "footlength", "footWidthCm": "footbreadthhorizontal",
        "armSpanCm": "span", "sittingHeightCm": "sittingheight", "thighCircumferenceCm": "thighcircumference",
        "calfCircumferenceCm": "calfcircumference", "upperArmCircumferenceCm": "bicepscircumferenceflexed",
        "forearmCircumferenceCm": "forearmcircumferenceflexed", "wristCircumferenceCm": "wristcircumference",
        "ankleCircumferenceCm": "anklecircumference", "headCircumferenceCm": "headcircumference",
        "headWidthCm": "headbreadth", "headLengthCm": "headlength", "kneeHeightCm": "kneeheightsitting"]

    private(set) var male = Sex()
    private(set) var female = Sex()

    static var bundled: AnthropometryModel? = {
        guard let url = Bundle.main.url(forResource: "ansur2-model", withExtension: "json",
                                        subdirectory: "CharacterReference") else { return nil }
        return try? AnthropometryModel(url: url)
    }()

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Anthropometry", code: 1, userInfo: [NSLocalizedDescriptionKey: "not a JSON object"])
        }
        male = Self.parse(root["male"])
        female = Self.parse(root["female"])
    }

    private static func parse(_ any: Any?) -> Sex {
        var s = Sex()
        guard let d = any as? [String: Any] else { return s }
        for (k, v) in (d["measurements"] as? [String: [String: Double]]) ?? [:] {
            s.stats[k] = Stat(mean: v["mean"] ?? 0, sd: v["sd"] ?? 0, p5: v["p5"] ?? 0, p50: v["p50"] ?? 0, p95: v["p95"] ?? 0)
        }
        for (k, v) in (d["vsStature"] as? [String: [String: Double]]) ?? [:] {
            s.vsStature[k] = Fit(slope: v["slope"] ?? 0, intercept: v["intercept"] ?? 0,
                                 residualSD: v["residualSD"] ?? 0, r: v["r"] ?? 0)
        }
        if let c = d["correlations"] as? [String: Any] {
            s.corrOrder = (c["order"] as? [String]) ?? []
            s.corr = (c["matrix"] as? [[Double]]) ?? []
        }
        return s
    }

    func sex(_ body: CharacterBody) -> Sex { body.baseModel == "female" ? female : male }

    /// Population weight (kg) for a height, from the stature regression.
    func predictedWeightKg(_ body: CharacterBody) -> Double? {
        let s = sex(body)
        guard let fit = s.vsStature["weightkg"] else { return nil }
        return (fit.intercept + fit.slope * body.heightCm * 10) / 10   // ANSUR weight is tenths of kg
    }

    /// One measurement for this body: override, or statistics conditioned on height (and weight when set).
    func measurement(_ name: String, for body: CharacterBody) -> BodyMeasurement? {
        if let v = body.manualOverrides[name] {
            return BodyMeasurement(name: name, value: v, source: .override, conditionalSD: 0)
        }
        guard let col = Self.columns[name] else { return nil }
        let s = sex(body)
        guard let y = s.stats[col] else { return nil }
        let c = min(max(body.correlationStrength, 0), 1)
        var predicted = y.mean
        var condSD = y.sd
        let hMM = body.heightCm * 10
        if let st = s.stats["stature"], let wt = s.stats["weightkg"], let w = body.weightKg,
           let rys = s.r(col, "stature"), let ryw = s.r(col, "weightkg"), let rsw = s.r("stature", "weightkg"),
           st.sd > 0, wt.sd > 0, abs(1 - rsw * rsw) > 1e-6 {
            // Gaussian conditional on height and weight:
            // mean_y + Σ_yx Σ_xx⁻¹ (x − mean_x), in standardized units
            let zs = (hMM - st.mean) / st.sd
            let zw = (w * 10 - wt.mean) / wt.sd
            let det = 1 - rsw * rsw
            let b1 = (rys - rsw * ryw) / det
            let b2 = (ryw - rsw * rys) / det
            predicted = y.mean + y.sd * (b1 * zs + b2 * zw)
            condSD = y.sd * sqrt(max(0.0, 1 - (b1 * rys + b2 * ryw)))
        } else if let fit = s.vsStature[col] {
            predicted = fit.intercept + fit.slope * hMM
            condSD = fit.residualSD
        }
        // correlation strength blends between the population mean and the prediction
        var value = y.mean + c * (predicted - y.mean)
        let sd = c > 0 ? condSD * c + y.sd * (1 - c) : y.sd
        value += (body.variation[name] ?? 0) * sd
        return BodyMeasurement(name: name, value: value / 10, source: c > 0 ? .predicted : .population, conditionalSD: sd / 10)
    }

    func allMeasurements(for body: CharacterBody) -> [BodyMeasurement] {
        Self.columns.keys.sorted().compactMap { measurement($0, for: body) }
    }

    // MARK: Self-test (DMXStudio --character-selftest path/to/ansur2-model.json)

    static func runSelfTest(modelPath: String) -> Bool {
        var ok = true
        func check(_ cond: Bool, _ msg: String) { print((cond ? "PASS " : "FAIL ") + msg); ok = ok && cond }
        guard let m = try? AnthropometryModel(url: URL(fileURLWithPath: modelPath)) else {
            print("FAIL cannot load \(modelPath)"); return false
        }
        check(m.male.stats.count > 90 && m.female.stats.count > 90, "model loads both sexes (\(m.male.stats.count), \(m.female.stats.count) measurements)")
        func v(_ n: String, _ b: CharacterBody) -> Double { m.measurement(n, for: b)?.value ?? .nan }

        var man = CharacterBody(); man.baseModel = "male"; man.heightCm = 175.5; man.correlationStrength = 1
        let sw = v("shoulderWidthCm", man)
        check(abs(sw - 41.5) < 1.5, "median-height man has ~41.5 cm shoulders (\(String(format: "%.1f", sw)))")

        var tall = man; tall.heightCm = 190
        var short = man; short.heightCm = 160
        let armT = v("upperArmLengthCm", tall), armS = v("upperArmLengthCm", short)
        check(armT > armS + 2, "height drives upper arm length (160 cm: \(String(format: "%.1f", armS)), 190 cm: \(String(format: "%.1f", armT)))")
        let neckT = v("neckCircumferenceCm", tall), neckS = v("neckCircumferenceCm", short)
        check((neckT - neckS) / neckS < (armT - armS) / armS, "neck follows height far less than arms do")

        var custom = tall; custom.manualOverrides["footLengthCm"] = 31
        check(v("footLengthCm", custom) == 31, "manual override wins")
        custom.heightCm = 165
        check(v("footLengthCm", custom) == 31, "manual override survives a height change")

        var off = man; off.correlationStrength = 0
        var offTall = off; offTall.heightCm = 195
        check(abs(v("upperArmLengthCm", off) - v("upperArmLengthCm", offTall)) < 0.01, "correlation 0: measurements ignore height")

        var longArms = man; longArms.variation["armSpanCm"] = 2
        var longArmsShort = longArms; longArmsShort.heightCm = 160
        let ref160 = v("armSpanCm", short)
        check(v("armSpanCm", longArmsShort) > ref160 + 5, "a long-armed character stays long-armed when height changes")

        var light = man; light.weightKg = 60
        var heavy = man; heavy.weightKg = 100
        let waistL = v("waistCircumferenceCm", light), waistH = v("waistCircumferenceCm", heavy)
        let boneL = v("upperArmLengthCm", light), boneH = v("upperArmLengthCm", heavy)
        check(waistH > waistL + 15, "weight changes circumference (waist \(String(format: "%.1f", waistL)) -> \(String(format: "%.1f", waistH)) cm)")
        check(abs(boneH - boneL) < 1.5, "weight barely changes bone length (upper arm \(String(format: "%.1f", boneL)) -> \(String(format: "%.1f", boneH)) cm)")

        var woman = CharacterBody(); woman.baseModel = "female"; woman.heightCm = 162.6; woman.correlationStrength = 1
        let fsw = v("shoulderWidthCm", woman)
        check(abs(fsw - 36.5) < 1.5, "median-height woman has ~36.5 cm shoulders (\(String(format: "%.1f", fsw)))")

        // persistence: an older saved performer without a body still decodes; a body round-trips
        let legacy = #"{"role":"Vocalist","skin":2,"outfit":0,"hairColor":0,"hair":"Short","height":1.8,"build":1}"#
        let old = try? JSONDecoder().decode(PerformerAppearance.self, from: Data(legacy.utf8))
        check(old != nil && old?.body == nil && abs((old?.resolvedBody.heightCm ?? 0) - 180) < 0.01, "older performer files load unchanged")
        var a = PerformerAppearance(); a.body = custom
        let round = (try? JSONEncoder().encode(a)).flatMap { try? JSONDecoder().decode(PerformerAppearance.self, from: $0) }
        check(round?.body == custom, "body parameters and overrides save and reload")

        print(ok ? "CHARACTER_SELFTEST_PASSED" : "CHARACTER_SELFTEST_FAILED")
        return ok
    }
}
