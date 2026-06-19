// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
#if canImport(FirebaseFirestore)
@_exported import FirebaseFirestore

extension Firestore: @retroactive @unchecked Sendable {}
extension CollectionReference: @retroactive @unchecked Sendable {}
#elseif SKIP
import Foundation
import SkipFirebaseCore
import kotlinx.coroutines.tasks.await

public typealias Timestamp = SkipFirebaseCore.Timestamp

// MARK: - GeoPoint

public final class GeoPoint: Hashable, Codable, KotlinConverting<com.google.firebase.firestore.GeoPoint> {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.GeoPoint {
        return com.google.firebase.firestore.GeoPoint(latitude, longitude)
    }

    public var description: String { "GeoPoint(\(latitude), \(longitude))" }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(latitude)
        hasher.combine(longitude)
    }

    private enum CodingKeys: String, CodingKey {
        case latitude = "__fgp_lat__"
        case longitude = "__fgp_lng__"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        self.longitude = try container.decode(Double.self, forKey: .longitude)
    }
}

// MARK: - VectorValue

public final class VectorValue: Hashable, Codable, KotlinConverting<com.google.firebase.firestore.VectorValue> {
    public let array: [Double]

    public init(_ array: [Double]) {
        self.array = array
    }

    public init(vector: com.google.firebase.firestore.VectorValue) {
        self.array = Array(vector.toArray().asList())
    }

    public var vector: com.google.firebase.firestore.VectorValue {
        kotlin()
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.VectorValue {
        // SKIP REPLACE: return com.google.firebase.firestore.FieldValue.vector(array.kotlin(nocopy = true).map { it as Double }.toDoubleArray())
        return com.google.firebase.firestore.FieldValue.vector(array.toDoubleArray())
    }

    public var description: String {
        "VectorValue(\(array))"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.array == rhs.array
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(array)
    }

    private enum CodingKeys: String, CodingKey {
        case array = "__fvv_array__"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(array, forKey: .array)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.array = try container.decode([Double].self, forKey: .array)
    }
}


// MARK: - Firestore-aware deep conversion (adds GeoPoint/VectorValue on top of Core's deepSwift)

fileprivate func firestoreDeepSwift(value: Any?) -> Any? {
    guard let value = value else { return nil }
    if let str = value as? String { return str }
    if let ts = value as? com.google.firebase.Timestamp {
        return Timestamp(timestamp: ts)
    }
    if let gp = value as? com.google.firebase.firestore.GeoPoint {
        return GeoPoint(latitude: gp.latitude, longitude: gp.longitude)
    }
    if let vector = value as? com.google.firebase.firestore.VectorValue {
        return VectorValue(vector: vector)
    }
    if let ref = value as? com.google.firebase.firestore.DocumentReference {
        return DocumentReference(ref: ref)
    }
    if let map = value as? kotlin.collections.Map<Any?, Any?> {
        return firestoreDeepSwift(map: map)
    }
    if let collection = value as? kotlin.collections.Collection<Any?> {
        return firestoreDeepSwift(collection: collection)
    }
    return value
}

fileprivate func firestoreDeepSwift<T>(map: kotlin.collections.Map<T, Any?>) -> Dictionary<T, Any> {
    var dict = Dictionary<T, Any>()
    for (key, val) in map {
        if let v = firestoreDeepSwift(value: val) {
            dict[key] = v
        }
    }
    return dict
}

fileprivate func firestoreDeepSwift(collection: kotlin.collections.Collection<Any?>) -> [Any] {
    var array = [Any]()
    for val in collection {
        if let v = firestoreDeepSwift(value: val) {
            array.append(v)
        }
    }
    return array
}

fileprivate func firestoreDeepSwiftNullable<T>(map: kotlin.collections.Map<T, Any?>) -> Dictionary<T, Any?> {
    var dict = Dictionary<T, Any?>()
    for (key, val) in map {
        dict[key] = firestoreDeepSwift(value: val)
    }
    return dict
}

// MARK: - Codable property wrappers

extension CodingUserInfoKey {
    static let firestoreDocumentID = CodingUserInfoKey(rawValue: "__firestore_document_id_key__")!
}

private enum _DocumentIDCodingKey: String, CodingKey {
    case value = "__document_id__"
}

/// Marks a `String?` property to be populated with the Firestore document ID during decoding.
/// The property is not written back to the document on encode.
/// Usage: `@DocumentID var id: String?`
// SKIP REPLACE: @Target(AnnotationTarget.FIELD) @Retention(AnnotationRetention.RUNTIME) annotation class DocumentID
@propertyWrapper
public struct DocumentID<Value: Codable>: Codable {
    public var wrappedValue: Value?

    public init(wrappedValue: Value? = nil) {
        self.wrappedValue = wrappedValue
    }

    public func encode(to encoder: Encoder) throws {
        // document ID is not stored in the document data
    }

    public init(from decoder: Decoder) throws {
        // Primary: read from userInfo (set by FirestoreDecoder.decode(from:documentID:))
        if let id = decoder.userInfo[CodingUserInfoKey.firestoreDocumentID] as? String {
            wrappedValue = id as? Value
            return
        }
        // Fallback: read the __document_id__ key injected into the top-level dict
        // This path is taken when decoder.userInfo is not available (e.g. some Skip runtimes)
        if let container = try? decoder.container(keyedBy: _DocumentIDCodingKey.self),
           let id = try? container.decodeIfPresent(String.self, forKey: .value) {
            wrappedValue = id as? Value
            return
        }
        wrappedValue = nil
    }
}

private struct _ServerTimestampSentinel: Encodable {
    private enum CodingKeys: String, CodingKey { case marker = "__fts_server__" }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(true, forKey: .marker)
    }
}

/// Marks a `Timestamp?` property so that a nil value is written as `FieldValue.serverTimestamp()`.
/// A non-nil value is written as the actual `Timestamp`.
/// Usage: `@ServerTimestamp var createdAt: Timestamp?`
// SKIP REPLACE: @Target(AnnotationTarget.FIELD) @Retention(AnnotationRetention.RUNTIME) annotation class ServerTimestamp
@propertyWrapper
public struct ServerTimestamp: Codable {
    public var wrappedValue: Timestamp?

    public init(wrappedValue: Timestamp? = nil) {
        self.wrappedValue = wrappedValue
    }

    public func encode(to encoder: Encoder) throws {
        if let ts = wrappedValue {
            try ts.encode(to: encoder)
        } else {
            try _ServerTimestampSentinel().encode(to: encoder)
        }
    }

    public init(from decoder: Decoder) throws {
        wrappedValue = try? Timestamp(from: decoder)
    }
}

// MARK: - Cache settings

public let FirestoreCacheSizeUnlimited: Int64 = -1

public protocol FirestoreCacheSettings {}

public protocol MemoryGarbageCollectionSettings {}

public struct MemoryLRUGCSettings: MemoryGarbageCollectionSettings {
    public var cacheSize: Int64
    public init(cacheSize: Int64 = FirestoreCacheSizeUnlimited) {
        self.cacheSize = cacheSize
    }
}

public struct MemoryEagerGCSettings: MemoryGarbageCollectionSettings {
    public init() {}
}

public struct MemoryCacheSettings: FirestoreCacheSettings {
    public var garbageCollectionSettings: MemoryGarbageCollectionSettings
    public init(garbageCollectionSettings: MemoryGarbageCollectionSettings = MemoryLRUGCSettings()) {
        self.garbageCollectionSettings = garbageCollectionSettings
    }
}

public struct PersistentCacheSettings: FirestoreCacheSettings {
    public var sizeBytes: Int64
    public init(sizeBytes: Int64 = FirestoreCacheSizeUnlimited) {
        self.sizeBytes = sizeBytes
    }
}

// MARK: - FirestoreSettings

public class FirestoreSettings {
    public var host: String = "firestore.googleapis.com"
    public var isSSLEnabled: Bool = true
    public var cacheSettings: FirestoreCacheSettings = PersistentCacheSettings()

    public init() {}

    func toAndroid() -> com.google.firebase.firestore.FirebaseFirestoreSettings {
        let builder = com.google.firebase.firestore.FirebaseFirestoreSettings.Builder()
        _ = builder.setHost(host)
        _ = builder.setSslEnabled(isSSLEnabled)
        if let persistent = cacheSettings as? PersistentCacheSettings {
            let cacheBuilder = com.google.firebase.firestore.PersistentCacheSettings.newBuilder()
            if persistent.sizeBytes != FirestoreCacheSizeUnlimited {
                _ = cacheBuilder.setSizeBytes(persistent.sizeBytes)
            }
            _ = builder.setLocalCacheSettings(cacheBuilder.build())
        } else if cacheSettings is MemoryCacheSettings {
            let cacheBuilder = com.google.firebase.firestore.MemoryCacheSettings.newBuilder()
            _ = builder.setLocalCacheSettings(cacheBuilder.build())
        }
        return builder.build()
    }
}

// https://firebase.google.com/docs/reference/swift/firebasefirestore/api/reference/Classes/Firestore
// https://firebase.google.com/docs/reference/android/com/google/firebase/firestore/FirebaseFirestore

public final class Firestore: KotlinConverting<com.google.firebase.firestore.FirebaseFirestore> {
    public let store: com.google.firebase.firestore.FirebaseFirestore
    private var _settings: FirestoreSettings = FirestoreSettings()

    public init(store: com.google.firebase.firestore.FirebaseFirestore) {
        self.store = store
    }

    public var description: String {
        store.toString()
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.FirebaseFirestore {
        store
    }

    public var settings: FirestoreSettings {
        get { _settings }
        set {
            _settings = newValue
            store.firestoreSettings = newValue.toAndroid()
        }
    }

    public static func firestore(app: FirebaseApp, database: String) -> Firestore {
        return Firestore(store: com.google.firebase.firestore.FirebaseFirestore.getInstance(app.app, database))
    }

    public static func firestore(app: FirebaseApp) -> Firestore {
        return Firestore(store: com.google.firebase.firestore.FirebaseFirestore.getInstance(app.app))
    }

    public static func firestore(database: String) -> Firestore {
        return Firestore(store: com.google.firebase.firestore.FirebaseFirestore.getInstance(database))
    }

    public static func firestore() -> Firestore {
        return Firestore(store: com.google.firebase.firestore.FirebaseFirestore.getInstance())
    }

    public func pipeline() -> PipelineSource {
        PipelineSource(source: store.pipeline(), firestore: store)
    }

    public func collection(_ collectionPath: String) -> CollectionReference {
        CollectionReference(ref: store.collection(collectionPath))
    }

    public func terminate() async {
        store.terminate().await()
    }

    public func clearPersistence() async {
        store.clearPersistence().await()
    }

    public func disableNetwork() async {
        store.disableNetwork().await()
    }

    public func enableNetwork() async {
        store.enableNetwork().await()
    }

    public func loadBundle(_ data: Data) async -> LoadBundleTaskProgress {
        return LoadBundleTaskProgress(progress: store.loadBundle(data.kotlin()).await())
    }

    public func getQuery(named name: String) async -> Query? {
        guard let query = store.getNamedQuery(name).await() else {
            return nil
        }
        return Query(query: query)
    }

    public func collectionGroup(collectionId: String) -> Query {
        return Query(query: store.collectionGroup(collectionId))
    }

    public func batch() -> WriteBatch {
        return WriteBatch(batch: store.batch())
    }

    public func useEmulator(withHost host: String, port: Int) {
        store.useEmulator(host, port)
    }

    public func document(_ path: String) -> DocumentReference {
        DocumentReference(ref: store.document(path))
    }
}

/// A FieldPath refers to a field in a document. The path may consist of a single field name (referring to a top level field in the document), or a list of field names (referring to a nested field in the document).
public class FieldPath : Hashable, KotlinConverting<com.google.firebase.firestore.FieldPath> {
    public let fieldPath: com.google.firebase.firestore.FieldPath

    public init(fieldPath: com.google.firebase.firestore.FieldPath) {
        self.fieldPath = fieldPath
    }

    public init(_ fieldNames: [String]) {
        let fnames = fieldNames.toList().toTypedArray()
        self.fieldPath = com.google.firebase.firestore.FieldPath.of(*fnames)
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.FieldPath {
        fieldPath
    }

    public var description: String {
        fieldPath.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.fieldPath == rhs.fieldPath
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fieldPath.hashCode())
    }

    /// A special sentinel FieldPath to refer to the ID of a document. It can be used in queries to sort or filter by the document ID.
    public static func documentID() -> FieldPath {
        FieldPath(fieldPath: com.google.firebase.firestore.FieldPath.documentId())
    }
}

public class LoadBundleTaskProgress: Equatable, KotlinConverting<com.google.firebase.firestore.LoadBundleTaskProgress> {
    public let progress: com.google.firebase.firestore.LoadBundleTaskProgress

    public init(progress: com.google.firebase.firestore.LoadBundleTaskProgress) {
        self.progress = progress
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.LoadBundleTaskProgress {
        progress
    }

    public var description: String {
        progress.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.progress == rhs.progress
    }

    public var totalDocuments: Int {
        progress.totalDocuments
    }

    public var documentsLoaded: Int {
        progress.documentsLoaded
    }

    public var bytesLoaded: Int64 {
        progress.bytesLoaded
    }

    public var totalBytes: Int64 {
        progress.totalBytes
    }

    public var state: LoadBundleTaskState {
        switch progress.taskState {
        case com.google.firebase.firestore.LoadBundleTaskProgress.TaskState.ERROR:
            return LoadBundleTaskState.error
        case com.google.firebase.firestore.LoadBundleTaskProgress.TaskState.RUNNING:
            return LoadBundleTaskState.inProgress
        case com.google.firebase.firestore.LoadBundleTaskProgress.TaskState.SUCCESS:
            return LoadBundleTaskState.success
        }
    }
}

public enum LoadBundleTaskState {
    case error
    case inProgress
    case success
}

/// A query that calculates aggregations over an underlying query.
public class AggregateQuery: Equatable, KotlinConverting<com.google.firebase.firestore.AggregateQuery> {
    public let query: com.google.firebase.firestore.AggregateQuery

    public init(query: com.google.firebase.firestore.AggregateQuery) {
        self.query = query
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.AggregateQuery {
        query
    }

    public var description: String {
        query.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query
    }

    public func getAggregation(source: AggregateSource) async throws -> AggregateQuerySnapshot {
        do {
            switch source {
            case .server:
                let snapshot = try query.get(com.google.firebase.firestore.AggregateSource.SERVER).await()
                return AggregateQuerySnapshot(snap: snapshot)
            }
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }
}

public class Filter: Equatable, KotlinConverting<com.google.firebase.firestore.Filter> {
    public let filter: com.google.firebase.firestore.Filter

    public init() {
        self.filter = com.google.firebase.firestore.Filter()
    }

    public init(filter: com.google.firebase.firestore.Filter) {
        self.filter = filter
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.Filter {
        filter
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.filter == rhs.filter
    }

    public static func whereField(_ field: String, isEqualTo value: Any) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.equalTo(field, value.kotlin()))
    }

    public static func whereField(_ field: String, isNotEqualTo value: Any, unusedp_0: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.notEqualTo(field, value.kotlin()))
    }

    public static func whereField(_ field: String, isGreaterThan value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.greaterThan(field, value.kotlin()))
    }

    public static func whereField(_ field: String, isGreaterThanOrEqualTo value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.greaterThanOrEqualTo(field, value.kotlin()))
    }

    public static func whereField(_ field: String, isLessThan value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil, unusedp_3: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.lessThan(field, value.kotlin()))
    }

    public static func whereField(_ field: String, isLessThanOrEqualTo value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil, unusedp_3: Nothing? = nil, unusedp_4: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.lessThanOrEqualTo(field, value.kotlin()))
    }

    public static func whereField(_ field: String, arrayContains value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil, unusedp_3: Nothing? = nil, unusedp_4: Nothing? = nil, unusedp_5: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.arrayContains(field, value.kotlin()))
    }

    public static func whereField(_ field: String, arrayContainsAny values: [Any]) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.arrayContainsAny(field, values.kotlin()))
    }

    public static func whereField(_ field: String, in values: [Any], unusedp_0: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.inArray(field, values.kotlin()))
    }

    public static func whereField(_ field: String, notIn values: [Any], unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.notInArray(field, values.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, isEqualTo value: Any) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.equalTo(fieldPath.fieldPath, value.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, isNotEqualTo value: Any, unusedp_0: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.notEqualTo(fieldPath.fieldPath, value.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, isGreaterThan value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.greaterThan(fieldPath.fieldPath, value.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, isGreaterThanOrEqualTo value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.greaterThanOrEqualTo(fieldPath.fieldPath, value.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, isLessThan value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil, unusedp_3: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.lessThan(fieldPath.fieldPath, value.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, isLessThanOrEqualTo value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil, unusedp_3: Nothing? = nil, unusedp_4: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.lessThanOrEqualTo(fieldPath.fieldPath, value.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, arrayContains value: Any, unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil, unusedp_2: Nothing? = nil, unusedp_3: Nothing? = nil, unusedp_4: Nothing? = nil, unusedp_5: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.arrayContains(fieldPath.fieldPath, value.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, arrayContainsAny values: [Any]) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.arrayContainsAny(fieldPath.fieldPath, values.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, in values: [Any], unusedp_0: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.inArray(fieldPath.fieldPath, values.kotlin()))
    }

    public static func whereField(_ fieldPath: FieldPath, notIn values: [Any], unusedp_0: Nothing? = nil, unusedp_1: Nothing? = nil) -> Filter {
        Filter(filter: com.google.firebase.firestore.Filter.notInArray(fieldPath.fieldPath, values.kotlin()))
    }

    public static func orFilter(_ filters: [Filter]) -> Filter {
        let platformFilters = filters.map(\.filter).toList().toTypedArray()
        return Filter(filter: com.google.firebase.firestore.Filter.or(*platformFilters))
    }

    public static func andFilter(_ filters: [Filter]) -> Filter {
        let platformFilters = filters.map(\.filter).toList().toTypedArray()
        return Filter(filter: com.google.firebase.firestore.Filter.and(*platformFilters))
    }
}

public class SnapshotMetadata: KotlinConverting<com.google.firebase.firestore.SnapshotMetadata> {
    public let meta: com.google.firebase.firestore.SnapshotMetadata

    public init(meta: com.google.firebase.firestore.SnapshotMetadata) {
        self.meta = meta
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.SnapshotMetadata {
        meta
    }

    public var description: String {
        meta.toString()
    }

    public var hasPendingWrites: Bool {
        meta.hasPendingWrites()
    }

    public var isFromCache: Bool {
        meta.isFromCache()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.meta == rhs.meta
    }
}

public class Query: KotlinConverting<com.google.firebase.firestore.Query> {
    public let query: com.google.firebase.firestore.Query

    public init(query: com.google.firebase.firestore.Query) {
        self.query = query
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.Query {
        query
    }

    public var description: String {
        query.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.query == rhs.query
    }

    public func getDocuments() async throws -> QuerySnapshot {
        do {
            let snapshot = try query.get().await()
            return QuerySnapshot(snap: snapshot)
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func getDocuments(source: FirestoreSource) async throws -> QuerySnapshot {
        do {
            let snapshot = try query.get(source.source).await()
            return QuerySnapshot(snap: snapshot)
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public var count: AggregateQuery {
        AggregateQuery(query: query.count())
    }

    public func limit(to count: Int64) -> Query {
        Query(query: query.limit(count))
    }

    public func order(by fieldName: String) -> Query {
        Query(query: query.orderBy(fieldName))
    }

    public func order(by fieldName: String, descending: Bool) -> Query {
        Query(query: query.orderBy(fieldName, descending ? com.google.firebase.firestore.Query.Direction.DESCENDING : com.google.firebase.firestore.Query.Direction.ASCENDING))
    }

    public func whereFilter(_ filter: Filter) -> Query {
        Query(query: query.where(filter.filter))
    }

    public func whereField(_ field: String, in array: [Any]) -> Query {
        Query(query: query.whereIn(field, array.kotlin()))
    }

    // SKIP DECLARE: fun whereField(field: String, notIn: Array<Any>, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null): Query
    public func whereField(_ field: String, notIn: [Any]) -> Query {
        Query(query: query.whereNotIn(field, notIn.kotlin()))
    }

    public func whereField(_ field: String, isEqualTo: Any) -> Query {
        Query(query: query.whereEqualTo(field, isEqualTo.kotlin()))
    }

    public func whereField(_ field: String, isGreaterThan: Any) -> Query {
        Query(query: query.whereGreaterThan(field, isGreaterThan.kotlin()))
    }

    public func whereField(_ field: String, isGreaterThanOrEqualTo: Any) -> Query {
        Query(query: query.whereGreaterThanOrEqualTo(field, isGreaterThanOrEqualTo.kotlin()))
    }

    public func whereField(_ field: String, isNotEqualTo: Any) -> Query {
        Query(query: query.whereNotEqualTo(field, isNotEqualTo.kotlin()))
    }

    public func whereField(_ field: String, isLessThanOrEqualTo: Any) -> Query {
        Query(query: query.whereLessThanOrEqualTo(field, isLessThanOrEqualTo.kotlin()))
    }

    public func whereField(_ field: String, isLessThan: Any) -> Query {
        Query(query: query.whereLessThan(field, isLessThan.kotlin()))
    }

    public func whereField(_ field: String, arrayContains: Any) -> Query {
        Query(query: query.whereArrayContains(field, arrayContains.kotlin()))
    }

    public func whereField(_ field: FieldPath, in array: [Any]) -> Query {
        Query(query: query.whereIn(field.fieldPath, array.kotlin()))
    }

    // SKIP DECLARE: fun whereField(field: String, arrayContainsAny: Array<Any>, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null, @Suppress("UNUSED_PARAMETER") unusedp_1: Nothing? = null): Query
    public func whereField(_ field: String, arrayContainsAny: [Any]) -> Query {
        Query(query: query.whereArrayContainsAny(field, arrayContainsAny.kotlin()))
    }

    // SKIP DECLARE: fun whereField(field: FieldPath, notIn: Array<Any>, @Suppress("UNUSED_PARAMETER") unusedp_0: Nothing? = null, @Suppress("UNUSED_PARAMETER") unusedp_1: Nothing? = null, @Suppress("UNUSED_PARAMETER") unusedp_2: Nothing? = null): Query
    public func whereField(_ field: FieldPath, notIn: [Any]) -> Query {
        Query(query: query.whereNotIn(field.fieldPath, notIn.kotlin()))
    }

    public func whereField(_ field: FieldPath, isEqualTo: Any) -> Query {
        Query(query: query.whereEqualTo(field.fieldPath, isEqualTo.kotlin()))
    }

    public func whereField(_ field: FieldPath, isGreaterThan: Any) -> Query {
        Query(query: query.whereGreaterThan(field.fieldPath, isGreaterThan.kotlin()))
    }

    public func whereField(_ field: FieldPath, isGreaterThanOrEqualTo: Any) -> Query {
        Query(query: query.whereGreaterThanOrEqualTo(field.fieldPath, isGreaterThanOrEqualTo.kotlin()))
    }

    public func whereField(_ field: FieldPath, isNotEqualTo: Any) -> Query {
        Query(query: query.whereNotEqualTo(field.fieldPath, isNotEqualTo.kotlin()))
    }

    public func whereField(_ field: FieldPath, isLessThanOrEqualTo: Any) -> Query {
        Query(query: query.whereLessThanOrEqualTo(field.fieldPath, isLessThanOrEqualTo.kotlin()))
    }

    public func whereField(_ field: FieldPath, isLessThan: Any) -> Query {
        Query(query: query.whereLessThan(field.fieldPath, isLessThan.kotlin()))
    }

    public func whereField(_ field: FieldPath, arrayContains: Any) -> Query {
        Query(query: query.whereArrayContains(field.fieldPath, arrayContains.kotlin()))
    }

    public func whereField(_ field: FieldPath, arrayContainsAny: [Any]) -> Query {
        Query(query: query.whereArrayContainsAny(field.fieldPath, arrayContainsAny.kotlin()))
    }

    public func start(afterDocument: DocumentSnapshot) -> Query {
        Query(query: query.startAfter(afterDocument.kotlin()))
    }

    public func addSnapshotListener(_ listener: @escaping (QuerySnapshot?, Error?) -> ()) -> ListenerRegistration {
        ListenerRegistration(reg: query.addSnapshotListener { snapshot, error in
            let qs: QuerySnapshot? = snapshot == nil ? nil : QuerySnapshot(snap: snapshot!)
            let err: Error? = error == nil ? nil : asNSError(firestoreException: error!)
            listener(qs, err)
        })
    }

    public func addSnapshotListener(includeMetadataChanges: Bool, listener: @escaping (QuerySnapshot?, Error?) -> ()) -> ListenerRegistration {
        ListenerRegistration(reg: query.addSnapshotListener(includeMetadataChanges ? com.google.firebase.firestore.MetadataChanges.INCLUDE : com.google.firebase.firestore.MetadataChanges.EXCLUDE) { snapshot, error in
            let qs: QuerySnapshot? = snapshot == nil ? nil : QuerySnapshot(snap: snapshot!)
            let err: Error? = error == nil ? nil : asNSError(firestoreException: error!)
            listener(qs, err)
        })
    }
}

public class CollectionReference : Query {
    public var ref: com.google.firebase.firestore.CollectionReference {
        self.query as! com.google.firebase.firestore.CollectionReference
    }

    public init(ref: com.google.firebase.firestore.CollectionReference) {
        super.init(query: ref)
    }

    public var firestore: Firestore {
        Firestore(store: ref.firestore)
    }

    public var collectionID: String {
        ref.getId()
    }

    public var parent: DocumentReference? {
        guard let parent = ref.parent else { return nil }
        return DocumentReference(ref: parent)
    }

    public var path: String {
        ref.path
    }

    public func document(_ path: String) -> DocumentReference {
        DocumentReference(ref: ref.document(path))
    }

    public func document() -> DocumentReference {
        DocumentReference(ref: ref.document())
    }

    public func addDocument(data: [String: Any]) async throws -> DocumentReference {
        do {
            let ref = try ref.add(data.kotlin()).await()
            return DocumentReference(ref: ref)
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func addDocument(data: [String: Any], completion: @escaping (Error?) -> Void) {
        ref.add(data.kotlin())
            .addOnSuccessListener { _ in completion(nil) }
            .addOnFailureListener { exception in completion(ErrorException(exception)) }
    }

    public func addDocument<T: Encodable>(from value: T) async throws -> DocumentReference {
        let data = try FirestoreEncoder().encode(value)
        return try await addDocument(data: data)
    }
}

public class ListenerRegistration: KotlinConverting<com.google.firebase.firestore.ListenerRegistration> {
    public let reg: com.google.firebase.firestore.ListenerRegistration

    public init(reg: com.google.firebase.firestore.ListenerRegistration) {
        self.reg = reg
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.ListenerRegistration {
        reg
    }

    public var description: String {
        reg.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.reg == rhs.reg
    }

    public func remove() {
        reg.remove()
    }
}

public class Transaction: KotlinConverting<com.google.firebase.firestore.Transaction> {
    public let transaction: com.google.firebase.firestore.Transaction

    public init(transaction: com.google.firebase.firestore.Transaction) {
        self.transaction = transaction
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.Transaction {
        transaction
    }

    public var description: String {
        transaction.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.transaction == rhs.transaction
    }
}

public class QuerySnapshot: KotlinConverting<com.google.firebase.firestore.QuerySnapshot> {
    public let snap: com.google.firebase.firestore.QuerySnapshot

    public init(snap: com.google.firebase.firestore.QuerySnapshot) {
        self.snap = snap
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.QuerySnapshot {
        snap
    }

    public var description: String {
        snap.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snap == rhs.snap
    }

    public var count: Int {
        snap.size()
    }

    public var isEmpty: Bool {
        snap.isEmpty()
    }

    public var metadata: SnapshotMetadata {
        SnapshotMetadata(snap.metadata)
    }

    public var query: Query {
        Query(query: snap.query)
    }

    public var documents: [QueryDocumentSnapshot] {
        Array(snap.documents.map({ QueryDocumentSnapshot(snapshot: $0 as! com.google.firebase.firestore.QueryDocumentSnapshot) }))
    }

    public var documentChanges: [DocumentChange] {
        Array(snap.getDocumentChanges().map({ DocumentChange(change: $0) }))
    }

    public func documentChanges(includeMetadataChanges: Bool) -> [DocumentChange] {
        Array(snap.getDocumentChanges(includeMetadataChanges
           ? com.google.firebase.firestore.MetadataChanges.INCLUDE
           : com.google.firebase.firestore.MetadataChanges.EXCLUDE)
            .map({ DocumentChange(change: $0) }))
    }
}

public enum AggregateSource {
    case server
}

public enum FirestoreSource {
    case `default`
    case server
    case cache

    public var source: com.google.firebase.firestore.Source {
        switch self {
        case `default`: return com.google.firebase.firestore.Source.DEFAULT
        case cache: return com.google.firebase.firestore.Source.CACHE
        case server: return com.google.firebase.firestore.Source.SERVER
        }
    }
}

public struct AggregateField: KotlinConverting<com.google.firebase.firestore.AggregateField> {
    public let agg: com.google.firebase.firestore.AggregateField

    public init(agg: com.google.firebase.firestore.AggregateField) {
        self.agg = agg
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.AggregateField {
        agg
    }

    public var description: String {
        agg.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.agg == rhs.agg
    }

    public static func count() -> AggregateField {
        AggregateField(agg: com.google.firebase.firestore.AggregateField.count())
    }

    public static func average(_ fieldName: String) -> AggregateField {
        AggregateField(agg: com.google.firebase.firestore.AggregateField.average(fieldName))
    }

    public static func average(_ field: FieldPath) -> AggregateField {
        AggregateField(agg: com.google.firebase.firestore.AggregateField.average(field.fieldPath))
    }

    public static func sum(_ fieldName: String) -> AggregateField {
        AggregateField(agg: com.google.firebase.firestore.AggregateField.sum(fieldName))
    }

    public static func sum(_ field: FieldPath) -> AggregateField {
        AggregateField(agg: com.google.firebase.firestore.AggregateField.sum(field.fieldPath))
    }
}

public class AggregateQuerySnapshot: KotlinConverting<com.google.firebase.firestore.AggregateQuerySnapshot> {
    public let snap: com.google.firebase.firestore.AggregateQuerySnapshot

    public init(snap: com.google.firebase.firestore.AggregateQuerySnapshot) {
        self.snap = snap
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.AggregateQuerySnapshot {
        snap
    }

    public var description: String {
        snap.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snap == rhs.snap
    }

    public var count: Int64 {
        snap.count
    }

    public var query: AggregateQuery {
        AggregateQuery(query: snap.query)
    }

    public func get(_ aggregateField: AggregateField) -> Any? {
        guard let value = snap.get(aggregateField.agg) else {
            return nil
        }
        return firestoreDeepSwift(value: value)
    }
}

public class DocumentChange: KotlinConverting<com.google.firebase.firestore.DocumentChange> {
    public let change: com.google.firebase.firestore.DocumentChange

    public init(change: com.google.firebase.firestore.DocumentChange) {
        self.change = change
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.DocumentChange {
        change
    }

    public var description: String {
        change.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.change == rhs.change
    }

    public var document: QueryDocumentSnapshot {
        QueryDocumentSnapshot(snapshot: change.document)
    }

    public var type: DocumentChangeType {
        switch change.type {
        case com.google.firebase.firestore.DocumentChange.Type.ADDED:
            return DocumentChangeType.added
        case com.google.firebase.firestore.DocumentChange.Type.MODIFIED:
            return DocumentChangeType.modified
        case com.google.firebase.firestore.DocumentChange.Type.REMOVED:
            return DocumentChangeType.removed
        }
    }
}

public enum DocumentChangeType {
    case added
    case modified
    case removed
}

public class DocumentSnapshot: KotlinConverting<com.google.firebase.firestore.DocumentSnapshot> {
    public let doc: com.google.firebase.firestore.DocumentSnapshot

    public init(doc: com.google.firebase.firestore.DocumentSnapshot) {
        self.doc = doc
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.DocumentSnapshot {
        doc
    }

    public var description: String {
        doc.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.doc == rhs.doc
    }

    public var documentID: String {
        doc.getId()
    }

    public var exists: Bool {
        doc.exists()
    }

    public var metadata: SnapshotMetadata {
        SnapshotMetadata(meta: doc.getMetadata())
    }

    public var reference: DocumentReference {
        DocumentReference(ref: doc.reference)
    }

    public func data() -> [String: Any]? {
        if let data = doc.getData() {
            return firestoreDeepSwift(map: data)
        } else {
            return nil
        }
    }

    public func get(_ fieldName: String) -> Any? {
        guard let value = doc.get(fieldName) else {
            return nil
        }
        return firestoreDeepSwift(value: value)
    }

    public func get(_ fieldPath: FieldPath) -> Any? {
        guard let value = doc.get(fieldPath.fieldPath) else {
            return nil
        }
        return firestoreDeepSwift(value: value)
    }

    // NOTE: use return-type inference on Android:
    //   let model: MyModel = try snapshot.decoded()
    // On iOS use FirebaseFirestoreSwift's data(as: MyModel.self) instead.
    // @inline(__always) makes Skip emit a Kotlin `inline fun <reified T>`, so the
    // body is inlined at the call site (no JVM-callable `decoded` method, no broken
    // bridge JNI lookup) while staying reachable for native-Swift Android callers.
    @inline(__always)
    public func decoded<T: Decodable>() throws -> T {
        guard let dict = data() else {
            throw NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.notFound.rawValue, userInfo: [NSLocalizedDescriptionKey: "Document does not exist"])
        }
        return try FirestoreDecoder().decode(from: dict, documentID: documentID)
    }
}

public class QueryDocumentSnapshot : DocumentSnapshot {
    public var snapshot: com.google.firebase.firestore.QueryDocumentSnapshot {
        doc as! com.google.firebase.firestore.QueryDocumentSnapshot
    }

    public init(snapshot: com.google.firebase.firestore.QueryDocumentSnapshot) {
        super.init(doc: snapshot)
    }

    override public var reference: DocumentReference {
        DocumentReference(ref: snapshot.reference)
    }

    override public func data() -> [String: Any] {
        if let data = doc.getData() {
            return firestoreDeepSwift(map: data)
        } else {
            return [:]
        }
    }
}

public class DocumentReference: KotlinConverting<com.google.firebase.firestore.DocumentReference> {
    public let ref: com.google.firebase.firestore.DocumentReference

    public init(ref: com.google.firebase.firestore.DocumentReference) {
        self.ref = ref
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.DocumentReference {
        ref
    }

    public var description: String {
        ref.toString()
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ref == rhs.ref
    }

    public var firestore: Firestore {
        Firestore(store: ref.firestore)
    }

    public func getDocument() async throws -> DocumentSnapshot {
        do {
            let snapshot = try ref.get().await()
            return DocumentSnapshot(doc: snapshot)
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func getDocument(source: FirestoreSource) async throws -> DocumentSnapshot {
        do {
            let snapshot = try ref.get(source.source).await()
            return DocumentSnapshot(doc: snapshot)
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func getDocument(completion: @escaping (_ snapshot: DocumentSnapshot?, _ error: (any Error)?) -> Void) {
        ref.get().addOnSuccessListener { documentSnapshot in
            completion(DocumentSnapshot(doc: documentSnapshot), nil)
        }
        .addOnFailureListener { exception in
            completion(nil, ErrorException(exception))
        }
    }

    public var parent: CollectionReference {
        CollectionReference(ref: ref.parent)
    }

    public var documentID: String {
        ref.getId()
    }

    public var path: String {
        ref.path
    }

    public func delete() async throws {
        do {
            try ref.delete().await()
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func setData(_ keyValues: [String: Any], merge: Bool = false) async throws {
        do {
            if merge == true {
                try ref.set(keyValues.kotlin(), com.google.firebase.firestore.SetOptions.merge()).await()
            } else {
                try ref.set(keyValues.kotlin()).await()
            }
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func setData(_ keyValues: [String: Any], mergeFields: [String]) async throws {
        do {
            try ref.set(keyValues.kotlin(), com.google.firebase.firestore.SetOptions.mergeFields(mergeFields.toList())).await()
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func setData<T: Encodable>(from value: T, merge: Bool = false) async throws {
        let data = try FirestoreEncoder().encode(value)
        try await setData(data, merge: merge)
    }

    public func setData<T: Encodable>(from value: T, mergeFields: [String]) async throws {
        let data = try FirestoreEncoder().encode(value)
        try await setData(data, mergeFields: mergeFields)
    }

    public func updateData(_ keyValues: [String: Any]) async throws {
        do {
            try ref.update(keyValues.kotlin() as! Map<String, Any>).await()
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func collection(_ collectionPath: String) -> CollectionReference {
        CollectionReference(ref: ref.collection(collectionPath))
    }

    public func addSnapshotListener(_ listener: @escaping (DocumentSnapshot?, Error?) -> ()) -> ListenerRegistration {
        ListenerRegistration(reg: ref.addSnapshotListener { snapshot, error in
            let ds: DocumentSnapshot? = snapshot == nil ? nil : DocumentSnapshot(doc: snapshot!)
            let err: Error? = error == nil ? nil : asNSError(firestoreException: error!)
            listener(ds, err)
        })
    }

    public func addSnapshotListener(includeMetadataChanges: Bool, listener: @escaping (DocumentSnapshot?, Error?) -> ()) -> ListenerRegistration {
        ListenerRegistration(reg: ref.addSnapshotListener(includeMetadataChanges ? com.google.firebase.firestore.MetadataChanges.INCLUDE : com.google.firebase.firestore.MetadataChanges.EXCLUDE) { snapshot, error in
            let ds: DocumentSnapshot? = snapshot == nil ? nil : DocumentSnapshot(doc: snapshot!)
            let err: Error? = error == nil ? nil : asNSError(firestoreException: error!)
            listener(ds, err)
        })
    }
}

public class WriteBatch {
    public let batch: com.google.firebase.firestore.WriteBatch

    public init(batch: com.google.firebase.firestore.WriteBatch) {
        self.batch = batch
    }

    public func commit() async throws {
        do {
            try batch.commit().await()
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        }
    }

    public func deleteDocument(_ document: DocumentReference) -> WriteBatch {
        let newBatch = batch.delete(document.ref)
        return WriteBatch(batch: newBatch)
    }

    public func setData( _ data: [String : Any], forDocument document: DocumentReference) -> WriteBatch {
        let newBatch = batch.set(document.ref, data.kotlin())
        return WriteBatch(batch: newBatch)
    }

    public func setData(_ data: [String : Any], forDocument document: DocumentReference, mergeFields: [String]) -> WriteBatch {
        let newBatch = batch.set(document.ref, data.kotlin(), com.google.firebase.firestore.SetOptions.mergeFields(mergeFields.toList()))
        return WriteBatch(batch: newBatch)
    }

    public func updateData(_ fields: [AnyHashable : Any], forDocument document: DocumentReference) -> WriteBatch {
        let newBatch = batch.update(document.ref, fields.kotlin() as! Map<String, Any>)
        return WriteBatch(batch: newBatch)
    }

    public func setData<T: Encodable>(from value: T, forDocument document: DocumentReference) throws -> WriteBatch {
        let data = try FirestoreEncoder().encode(value)
        return setData(data, forDocument: document)
    }

    public func setData<T: Encodable>(from value: T, forDocument document: DocumentReference, mergeFields: [String]) throws -> WriteBatch {
        let data = try FirestoreEncoder().encode(value)
        return setData(data, forDocument: document, mergeFields: mergeFields)
    }
}

// MARK: - Firestore Pipelines

fileprivate func pipelineInvalidArgumentError(_ message: String) -> Error {
    NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.invalidArgument.rawValue, userInfo: [NSLocalizedDescriptionKey: message])
}

fileprivate func pipelineRawValue(_ value: Any?) -> Any? {
    guard let value = value else { return nil }
    if let expression = value as? Expression { return expression.expression }
    if let aggregate = value as? AggregateFunction { return aggregate.aggregate }
    if let ordering = value as? Ordering { return ordering.ordering }
    if let field = value as? Field { return field.field }
    if let vector = value as? VectorValue { return vector.vector }
    if let geoPoint = value as? GeoPoint { return geoPoint.kotlin() }
    if let timestamp = value as? Timestamp { return timestamp.kotlin() }
    if let reference = value as? DocumentReference { return reference.ref }
    if let data = value as? Data { return com.google.firebase.firestore.Blob.fromBytes(data.kotlin()) }
    if let array = value as? [Any?] { return array.map { pipelineRawValue($0) } }
    if let dict = value as? [String: Any?] {
        var raw = [String: Any?]()
        for (key, val) in dict {
            raw[key] = pipelineRawValue(val)
        }
        return raw
    }
    return value.kotlin()
}

fileprivate func pipelineRawValueNonNil(_ value: Any) -> Any {
    pipelineRawValue(value)!
}

fileprivate func pipelineMapExpression(_ value: [String: Any?]) -> com.google.firebase.firestore.pipeline.Expression {
    var elements = [com.google.firebase.firestore.pipeline.Expression]()
    for (key, val) in value {
        elements.append(com.google.firebase.firestore.pipeline.Expression.constant(key))
        elements.append(pipelineConstantExpression(val))
    }
    let platformElements = elements.toList().toTypedArray()
    return com.google.firebase.firestore.pipeline.Expression.rawFunction("map", *platformElements)
}

fileprivate func pipelineConstantExpression(_ value: Any?) -> com.google.firebase.firestore.pipeline.Expression {
    guard let value = value else {
        return com.google.firebase.firestore.pipeline.Expression.nullValue()
    }
    if let expression = value as? Expression { return expression.expression }
    if let str = value as? String { return com.google.firebase.firestore.pipeline.Expression.constant(str) }
    if let bool = value as? Bool { return com.google.firebase.firestore.pipeline.Expression.constant(bool) }
    if let int = value as? Int { return com.google.firebase.firestore.pipeline.Expression.constant(int) }
    if let int64 = value as? Int64 { return com.google.firebase.firestore.pipeline.Expression.constant(int64) }
    if let double = value as? Double { return com.google.firebase.firestore.pipeline.Expression.constant(double) }
    if let date = value as? Date { return com.google.firebase.firestore.pipeline.Expression.constant(date.kotlin()) }
    if let timestamp = value as? Timestamp { return com.google.firebase.firestore.pipeline.Expression.constant(timestamp.kotlin()) }
    if let geoPoint = value as? GeoPoint { return com.google.firebase.firestore.pipeline.Expression.constant(geoPoint.kotlin()) }
    if let vector = value as? VectorValue { return com.google.firebase.firestore.pipeline.Expression.constant(vector.vector) }
    if let reference = value as? DocumentReference { return com.google.firebase.firestore.pipeline.Expression.constant(reference.ref) }
    if let data = value as? Data { return com.google.firebase.firestore.pipeline.Expression.constant(com.google.firebase.firestore.Blob.fromBytes(data.kotlin())) }
    if let array = value as? [Any?] {
        return com.google.firebase.firestore.pipeline.Expression.array(array.map { pipelineRawValue($0) }.toList())
    }
    if let dict = value as? [String: Any?] {
        return pipelineMapExpression(dict)
    }
    return com.google.firebase.firestore.pipeline.Expression.constant("\(value)")
}

fileprivate func duplicateSelectableAliasMessage(_ selectables: [Selectable]) -> String? {
    var aliases = Set<String>()
    for selectable in selectables {
        if aliases.contains(selectable.pipelineAlias) {
            return "Duplicate alias '\(selectable.pipelineAlias)' found in selectables."
        }
        aliases.insert(selectable.pipelineAlias)
    }
    return nil
}

fileprivate func duplicateAggregateAliasMessage(_ aggregates: [AliasedAggregate]) -> String? {
    var aliases = Set<String>()
    for aggregate in aggregates {
        if aliases.contains(aggregate.alias) {
            return "Duplicate alias '\(aggregate.alias)' found in accumulators."
        }
        aliases.insert(aggregate.alias)
    }
    return nil
}

fileprivate func pipelineRawFunctionExpression(_ name: String, _ args: [Expression]) -> com.google.firebase.firestore.pipeline.Expression {
    let platformArgs = args.map(\.expression).toList().toTypedArray()
    return com.google.firebase.firestore.pipeline.Expression.rawFunction(name, *platformArgs)
}

fileprivate func pipelineRawBooleanFunctionExpression(_ name: String, _ args: [Expression]) -> com.google.firebase.firestore.pipeline.BooleanExpression {
    let platformArgs = args.map(\.expression).toList().toTypedArray()
    return com.google.firebase.firestore.pipeline.BooleanExpression.rawFunction(name, *platformArgs)
}

fileprivate func pipelineExpressionArgument(_ value: Any?) -> Expression {
    if let expression = value as? Expression { return expression }
    return Constant(value)
}

fileprivate func pipelineFunction(_ name: String, _ args: [Any]) -> FunctionExpression {
    FunctionExpression(functionName: name, args: args.map { pipelineExpressionArgument($0) })
}

fileprivate func pipelineBooleanFunction(_ name: String, _ args: [Any]) -> BooleanExpression {
    BooleanExpression(expression: pipelineRawBooleanFunctionExpression(name, args.map { pipelineExpressionArgument($0) }))
}

fileprivate func pipelineArrayExpression(_ values: [Any]) -> Expression {
    ArrayExpression(values)
}

fileprivate func pipelineMapExpressionArguments(_ elements: [String: Any]) -> [Expression] {
    var args = [Expression]()
    for (key, value) in elements {
        args.append(Constant(key))
        args.append(pipelineExpressionArgument(value))
    }
    return args
}

fileprivate func pipelineArguments(_ first: Any, _ rest: [Any]) -> [Any] {
    var args = [first]
    args.append(contentsOf: rest)
    return args
}

fileprivate func pipelineArguments(_ first: Any, _ second: Any, _ third: Any, _ rest: [Any]) -> [Any] {
    var args = [first, second, third]
    args.append(contentsOf: rest)
    return args
}

public protocol Selectable {
    var pipelineSelectable: com.google.firebase.firestore.pipeline.Selectable { get }
    var pipelineExpression: Expression { get }
    var pipelineAlias: String { get }
}

public class Expression: KotlinConverting<com.google.firebase.firestore.pipeline.Expression> {
    public let expression: com.google.firebase.firestore.pipeline.Expression

    public init(expression: com.google.firebase.firestore.pipeline.Expression) {
        self.expression = expression
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.pipeline.Expression {
        expression
    }

    public var description: String { expression.toString() }

    public func `as`(_ name: String) -> AliasedExpression {
        AliasedExpression(self, name)
    }

    public func asBoolean() -> BooleanExpression {
        BooleanExpression(expression: expression as! com.google.firebase.firestore.pipeline.BooleanExpression)
    }

    public func ascending() -> Ordering {
        Ordering(ordering: com.google.firebase.firestore.pipeline.Ordering.ascending(expression))
    }

    public func descending() -> Ordering {
        Ordering(ordering: com.google.firebase.firestore.pipeline.Ordering.descending(expression))
    }

    public func equal(_ value: Any?) -> BooleanExpression {
        guard let value else {
            return BooleanExpression(expression: expression.equal(com.google.firebase.firestore.pipeline.Expression.nullValue()))
        }
        return BooleanExpression(expression: expression.equal(pipelineRawValueNonNil(value)))
    }

    public func equal(_ other: Expression) -> BooleanExpression {
        BooleanExpression(expression: expression.equal(other.expression))
    }

    public func notEqual(_ value: Any?) -> BooleanExpression {
        guard let value else {
            return BooleanExpression(expression: expression.notEqual(com.google.firebase.firestore.pipeline.Expression.nullValue()))
        }
        return BooleanExpression(expression: expression.notEqual(pipelineRawValueNonNil(value)))
    }

    public func greaterThan(_ value: Any) -> BooleanExpression {
        BooleanExpression(expression: expression.greaterThan(pipelineRawValueNonNil(value)))
    }

    public func greaterThan(_ other: Expression) -> BooleanExpression {
        BooleanExpression(expression: expression.greaterThan(other.expression))
    }

    public func greaterThanOrEqual(_ value: Any) -> BooleanExpression {
        BooleanExpression(expression: expression.greaterThanOrEqual(pipelineRawValueNonNil(value)))
    }

    public func lessThan(_ value: Any) -> BooleanExpression {
        BooleanExpression(expression: expression.lessThan(pipelineRawValueNonNil(value)))
    }

    public func lessThan(_ other: Expression) -> BooleanExpression {
        BooleanExpression(expression: expression.lessThan(other.expression))
    }

    public func lessThanOrEqual(_ value: Any) -> BooleanExpression {
        BooleanExpression(expression: expression.lessThanOrEqual(pipelineRawValueNonNil(value)))
    }

    public func lessThanOrEqual(_ other: Expression) -> BooleanExpression {
        BooleanExpression(expression: expression.lessThanOrEqual(other.expression))
    }

    public func exists() -> BooleanExpression {
        BooleanExpression(expression: expression.exists())
    }

    public func isError() -> BooleanExpression {
        pipelineBooleanFunction("is_error", [self])
    }

    public func isAbsent() -> BooleanExpression {
        pipelineBooleanFunction("is_absent", [self])
    }

    public func add(_ value: Any) -> FunctionExpression {
        FunctionExpression(expression: expression.add(pipelineConstantExpression(value)))
    }

    public func add(_ other: Expression) -> FunctionExpression {
        FunctionExpression(expression: expression.add(other.expression))
    }

    public func subtract(_ value: Any) -> FunctionExpression {
        FunctionExpression(expression: expression.subtract(pipelineConstantExpression(value)))
    }

    public func subtract(_ other: Expression) -> FunctionExpression {
        FunctionExpression(expression: expression.subtract(other.expression))
    }

    public func multiply(_ value: Any) -> FunctionExpression {
        FunctionExpression(expression: expression.multiply(pipelineConstantExpression(value)))
    }

    public func multiply(_ other: Expression) -> FunctionExpression {
        FunctionExpression(expression: expression.multiply(other.expression))
    }

    public func divide(_ value: Any) -> FunctionExpression {
        FunctionExpression(expression: expression.divide(pipelineConstantExpression(value)))
    }

    public func divide(_ other: Expression) -> FunctionExpression {
        FunctionExpression(expression: expression.divide(other.expression))
    }

    public func mod(_ value: Any) -> FunctionExpression {
        pipelineFunction("mod", [self, value])
    }

    public func mod(_ other: Expression) -> FunctionExpression {
        pipelineFunction("mod", [self, other])
    }

    public func abs() -> FunctionExpression {
        FunctionExpression(expression: expression.abs())
    }

    public func ceil() -> FunctionExpression {
        FunctionExpression(expression: expression.ceil())
    }

    public func floor() -> FunctionExpression {
        FunctionExpression(expression: expression.floor())
    }

    public func round() -> FunctionExpression {
        FunctionExpression(expression: expression.round())
    }

    public func sqrt() -> FunctionExpression {
        FunctionExpression(expression: expression.sqrt())
    }

    public func exp() -> FunctionExpression {
        pipelineFunction("exp", [self])
    }

    public func ln() -> FunctionExpression {
        pipelineFunction("ln", [self])
    }

    public func trunc() -> FunctionExpression {
        pipelineFunction("trunc", [self])
    }

    public func truncToPrecision(_ decimalPlace: Any) -> FunctionExpression {
        pipelineFunction("trunc", [self, decimalPlace])
    }

    public func truncToPrecision(_ decimalPlace: Expression) -> FunctionExpression {
        pipelineFunction("trunc", [self, decimalPlace])
    }

    public func pow(_ value: Any) -> FunctionExpression {
        FunctionExpression(expression: expression.pow(pipelineConstantExpression(value)))
    }

    public func pow(_ other: Expression) -> FunctionExpression {
        FunctionExpression(expression: expression.pow(other.expression))
    }

    public func toUpper() -> FunctionExpression {
        FunctionExpression(expression: expression.toUpper())
    }

    public func toLower() -> FunctionExpression {
        FunctionExpression(expression: expression.toLower())
    }

    public func getField(_ key: String) -> FunctionExpression {
        FunctionExpression(expression: expression.getField(key))
    }

    public func getField(_ key: Expression) -> FunctionExpression {
        pipelineFunction("get_field", [self, key])
    }

    public func arrayReverse() -> FunctionExpression {
        pipelineFunction("array_reverse", [self])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("arrayConcatExpressions")
    */
    public final func arrayConcat(_ arrays: [Expression]) -> FunctionExpression {
        pipelineFunction("array_concat", pipelineArguments(self, arrays.map { $0 as Any }))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("arrayConcatValues")
    */
    public final func arrayConcat(_ arrays: [[Any]]) -> FunctionExpression {
        pipelineFunction("array_concat", pipelineArguments(self, arrays.map { pipelineArrayExpression($0) as Any }))
    }

    public func arrayContains(_ value: Any) -> BooleanExpression {
        BooleanExpression(expression: expression.arrayContains(pipelineRawValueNonNil(value)))
    }

    public func arrayContains(_ element: Expression) -> BooleanExpression {
        pipelineBooleanFunction("array_contains", [self, element])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("arrayContainsAllExpressions")
    */
    public final func arrayContainsAll(_ values: [Expression]) -> BooleanExpression {
        pipelineBooleanFunction("array_contains_all", [self, pipelineArrayExpression(values.map { $0 as Any })])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("arrayContainsAllValues")
    */
    public final func arrayContainsAll(_ values: [Any]) -> BooleanExpression {
        pipelineBooleanFunction("array_contains_all", [self, pipelineArrayExpression(values)])
    }

    public func arrayContainsAll(_ arrayExpression: Expression) -> BooleanExpression {
        pipelineBooleanFunction("array_contains_all", [self, arrayExpression])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("arrayContainsAnyExpressions")
    */
    public final func arrayContainsAny(_ values: [Expression]) -> BooleanExpression {
        pipelineBooleanFunction("array_contains_any", [self, pipelineArrayExpression(values.map { $0 as Any })])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("arrayContainsAnyValues")
    */
    public final func arrayContainsAny(_ values: [Any]) -> BooleanExpression {
        pipelineBooleanFunction("array_contains_any", [self, pipelineArrayExpression(values)])
    }

    public func arrayContainsAny(_ arrayExpression: Expression) -> BooleanExpression {
        pipelineBooleanFunction("array_contains_any", [self, arrayExpression])
    }

    public func arrayLength() -> FunctionExpression {
        pipelineFunction("array_length", [self])
    }

    public func arrayFilter(alias: String, filter: BooleanExpression) -> FunctionExpression {
        pipelineFunction("array_filter", [self, Constant(alias), filter])
    }

    public func arrayTransform(elementAlias: String, transform: Expression) -> FunctionExpression {
        pipelineFunction("array_transform", [self, Constant(elementAlias), transform])
    }

    public func arrayTransformWithIndex(elementAlias: String, indexAlias: String, transform: Expression) -> FunctionExpression {
        pipelineFunction("array_transform_with_index", [self, Constant(elementAlias), Constant(indexAlias), transform])
    }

    public func arraySlice(offset: Int) -> FunctionExpression {
        pipelineFunction("array_slice", [self, offset])
    }

    public func arraySlice(offset: Expression) -> FunctionExpression {
        pipelineFunction("array_slice", [self, offset])
    }

    public func arraySlice(offset: Int, length: Int) -> FunctionExpression {
        pipelineFunction("array_slice", [self, offset, length])
    }

    public func arraySlice(offset: Expression, length: Expression) -> FunctionExpression {
        pipelineFunction("array_slice", [self, offset, length])
    }

    public func arraySlice(offset: Int, length: Expression) -> FunctionExpression {
        pipelineFunction("array_slice", [self, offset, length])
    }

    public func arraySlice(offset: Expression, length: Int) -> FunctionExpression {
        pipelineFunction("array_slice", [self, offset, length])
    }

    public func arrayFirst() -> FunctionExpression {
        pipelineFunction("array_first", [self])
    }

    public func arrayFirstN(_ n: Int) -> FunctionExpression {
        pipelineFunction("array_first_n", [self, n])
    }

    public func arrayFirstN(_ n: Expression) -> FunctionExpression {
        pipelineFunction("array_first_n", [self, n])
    }

    public func arrayLast() -> FunctionExpression {
        pipelineFunction("array_last", [self])
    }

    public func arrayLastN(_ n: Int) -> FunctionExpression {
        pipelineFunction("array_last_n", [self, n])
    }

    public func arrayLastN(_ n: Expression) -> FunctionExpression {
        pipelineFunction("array_last_n", [self, n])
    }

    public func arrayGet(_ offset: Int) -> FunctionExpression {
        pipelineFunction("array_get", [self, offset])
    }

    public func arrayGet(_ offsetExpression: Expression) -> FunctionExpression {
        pipelineFunction("array_get", [self, offsetExpression])
    }

    public func arrayIndexOf(_ value: Any) -> FunctionExpression {
        pipelineFunction("array_index_of", [self, value])
    }

    public func arrayIndexOf(_ value: Expression) -> FunctionExpression {
        pipelineFunction("array_index_of", [self, value])
    }

    public func arrayLastIndexOf(_ value: Any) -> FunctionExpression {
        pipelineFunction("array_last_index_of", [self, value])
    }

    public func arrayLastIndexOf(_ value: Expression) -> FunctionExpression {
        pipelineFunction("array_last_index_of", [self, value])
    }

    public func arrayIndexOfAll(_ value: Any) -> FunctionExpression {
        pipelineFunction("array_index_of_all", [self, value])
    }

    public func arrayIndexOfAll(_ value: Expression) -> FunctionExpression {
        pipelineFunction("array_index_of_all", [self, value])
    }

    public func arrayMaximum() -> FunctionExpression {
        pipelineFunction("array_maximum", [self])
    }

    public func arrayMinimum() -> FunctionExpression {
        pipelineFunction("array_minimum", [self])
    }

    public func arrayMinimumN(_ n: Int) -> FunctionExpression {
        pipelineFunction("array_minimum_n", [self, n])
    }

    public func arrayMinimumN(_ n: Expression) -> FunctionExpression {
        pipelineFunction("array_minimum_n", [self, n])
    }

    public func arrayMaximumN(_ n: Int) -> FunctionExpression {
        pipelineFunction("array_maximum_n", [self, n])
    }

    public func arrayMaximumN(_ n: Expression) -> FunctionExpression {
        pipelineFunction("array_maximum_n", [self, n])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("equalAnyExpressions")
    */
    public final func equalAny(_ others: [Expression]) -> BooleanExpression {
        pipelineBooleanFunction("equal_any", [self, pipelineArrayExpression(others.map { $0 as Any })])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("equalAnyValues")
    */
    public final func equalAny(_ others: [Any]) -> BooleanExpression {
        pipelineBooleanFunction("equal_any", [self, pipelineArrayExpression(others)])
    }

    public func equalAny(_ arrayExpression: Expression) -> BooleanExpression {
        pipelineBooleanFunction("equal_any", [self, arrayExpression])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("notEqualAnyExpressions")
    */
    public final func notEqualAny(_ others: [Expression]) -> BooleanExpression {
        pipelineBooleanFunction("not_equal_any", [self, pipelineArrayExpression(others.map { $0 as Any })])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("notEqualAnyValues")
    */
    public final func notEqualAny(_ others: [Any]) -> BooleanExpression {
        pipelineBooleanFunction("not_equal_any", [self, pipelineArrayExpression(others)])
    }

    public func notEqualAny(_ arrayExpression: Expression) -> BooleanExpression {
        pipelineBooleanFunction("not_equal_any", [self, arrayExpression])
    }

    public func join(delimiter: String) -> FunctionExpression {
        pipelineFunction("join", [self, delimiter])
    }

    public func split(delimiter: String) -> FunctionExpression {
        pipelineFunction("split", [self, delimiter])
    }

    public func split(delimiter: Expression) -> FunctionExpression {
        pipelineFunction("split", [self, delimiter])
    }

    public func length() -> FunctionExpression {
        pipelineFunction("length", [self])
    }

    public func charLength() -> FunctionExpression {
        pipelineFunction("char_length", [self])
    }

    public func like(_ pattern: String) -> BooleanExpression {
        pipelineBooleanFunction("like", [self, pattern])
    }

    public func like(_ pattern: Expression) -> BooleanExpression {
        pipelineBooleanFunction("like", [self, pattern])
    }

    public func regexContains(_ pattern: String) -> BooleanExpression {
        pipelineBooleanFunction("regex_contains", [self, pattern])
    }

    public func regexContains(_ pattern: Expression) -> BooleanExpression {
        pipelineBooleanFunction("regex_contains", [self, pattern])
    }

    public func regexFind(_ pattern: String) -> FunctionExpression {
        pipelineFunction("regex_find", [self, pattern])
    }

    public func regexFind(_ pattern: Expression) -> FunctionExpression {
        pipelineFunction("regex_find", [self, pattern])
    }

    public func regexFindAll(_ pattern: String) -> FunctionExpression {
        pipelineFunction("regex_find_all", [self, pattern])
    }

    public func regexFindAll(_ pattern: Expression) -> FunctionExpression {
        pipelineFunction("regex_find_all", [self, pattern])
    }

    public func regexMatch(_ pattern: String) -> BooleanExpression {
        pipelineBooleanFunction("regex_match", [self, pattern])
    }

    public func regexMatch(_ pattern: Expression) -> BooleanExpression {
        pipelineBooleanFunction("regex_match", [self, pattern])
    }

    public func stringContains(_ substring: String) -> BooleanExpression {
        pipelineBooleanFunction("string_contains", [self, substring])
    }

    public func stringContains(_ expression: Expression) -> BooleanExpression {
        pipelineBooleanFunction("string_contains", [self, expression])
    }

    public func startsWith(_ prefix: String) -> BooleanExpression {
        pipelineBooleanFunction("starts_with", [self, prefix])
    }

    public func startsWith(_ prefix: Expression) -> BooleanExpression {
        pipelineBooleanFunction("starts_with", [self, prefix])
    }

    public func endsWith(_ suffix: String) -> BooleanExpression {
        pipelineBooleanFunction("ends_with", [self, suffix])
    }

    public func endsWith(_ suffix: Expression) -> BooleanExpression {
        pipelineBooleanFunction("ends_with", [self, suffix])
    }

    public func trim() -> FunctionExpression {
        pipelineFunction("trim", [self])
    }

    public func trim(_ value: String) -> FunctionExpression {
        pipelineFunction("trim", [self, value])
    }

    public func trim(_ value: Expression) -> FunctionExpression {
        pipelineFunction("trim", [self, value])
    }

    public func ltrim() -> FunctionExpression {
        pipelineFunction("ltrim", [self])
    }

    public func ltrim(_ value: String) -> FunctionExpression {
        pipelineFunction("ltrim", [self, value])
    }

    public func ltrim(_ value: Expression) -> FunctionExpression {
        pipelineFunction("ltrim", [self, value])
    }

    public func rtrim() -> FunctionExpression {
        pipelineFunction("rtrim", [self])
    }

    public func rtrim(_ value: String) -> FunctionExpression {
        pipelineFunction("rtrim", [self, value])
    }

    public func rtrim(_ value: Expression) -> FunctionExpression {
        pipelineFunction("rtrim", [self, value])
    }

    public func stringRepeat(_ count: Int) -> FunctionExpression {
        pipelineFunction("string_repeat", [self, count])
    }

    public func stringRepeat(_ count: Expression) -> FunctionExpression {
        pipelineFunction("string_repeat", [self, count])
    }

    public func stringReplaceAll(_ oldValue: String, with newValue: String) -> FunctionExpression {
        pipelineFunction("string_replace_all", [self, oldValue, newValue])
    }

    public func stringReplaceAll(_ oldValue: Expression, with newValue: Expression) -> FunctionExpression {
        pipelineFunction("string_replace_all", [self, oldValue, newValue])
    }

    public func stringReplaceOne(_ oldValue: String, with newValue: String) -> FunctionExpression {
        pipelineFunction("string_replace_one", [self, oldValue, newValue])
    }

    public func stringReplaceOne(_ oldValue: Expression, with newValue: Expression) -> FunctionExpression {
        pipelineFunction("string_replace_one", [self, oldValue, newValue])
    }

    public func stringIndexOf(_ substring: String) -> FunctionExpression {
        pipelineFunction("string_index_of", [self, substring])
    }

    public func stringIndexOf(_ substring: Expression) -> FunctionExpression {
        pipelineFunction("string_index_of", [self, substring])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("stringConcatValues")
    */
    public final func stringConcat(_ strings: [Any]) -> FunctionExpression {
        pipelineFunction("string_concat", pipelineArguments(self, strings))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("stringConcatExpressions")
    */
    public final func stringConcat(_ strings: [Expression]) -> FunctionExpression {
        pipelineFunction("string_concat", pipelineArguments(self, strings.map { $0 as Any }))
    }

    public func reverse() -> FunctionExpression {
        pipelineFunction("reverse", [self])
    }

    public func stringReverse() -> FunctionExpression {
        pipelineFunction("string_reverse", [self])
    }

    public func byteLength() -> FunctionExpression {
        pipelineFunction("byte_length", [self])
    }

    public func substring(position: Int, length: Int?) -> FunctionExpression {
        if let length {
            return pipelineFunction("substring", [self, position, length])
        }
        return pipelineFunction("substring", [self, position])
    }

    public func substring(position: Expression, length: Expression?) -> FunctionExpression {
        if let length {
            return pipelineFunction("substring", [self, position, length])
        }
        return pipelineFunction("substring", [self, position])
    }

    public func mapGet(_ subfield: String) -> FunctionExpression {
        pipelineFunction("map_get", [self, subfield])
    }

    public func mapGet(_ subfield: Expression) -> FunctionExpression {
        pipelineFunction("map_get", [self, subfield])
    }

    public func mapRemove(_ key: String) -> FunctionExpression {
        pipelineFunction("map_remove", [self, key])
    }

    public func mapRemove(_ keyExpression: Expression) -> FunctionExpression {
        pipelineFunction("map_remove", [self, keyExpression])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("mapMergeValues")
    */
    public final func mapMerge(_ maps: [[String: Any]]) -> FunctionExpression {
        pipelineFunction("map_merge", pipelineArguments(self, maps.map { MapExpression($0) as Any }))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("mapMergeExpressions")
    */
    public final func mapMerge(_ maps: [Expression]) -> FunctionExpression {
        pipelineFunction("map_merge", pipelineArguments(self, maps.map { $0 as Any }))
    }

    public func mapSet(_ key: Expression, _ value: Expression, _ moreKeyValues: [Expression] = []) -> FunctionExpression {
        pipelineFunction("map_set", pipelineArguments(self, key, value, moreKeyValues.map { $0 as Any }))
    }

    public func mapSet(_ key: String, _ value: Any, _ moreKeyValues: [Any] = []) -> FunctionExpression {
        pipelineFunction("map_set", pipelineArguments(self, key, value, moreKeyValues))
    }

    public func mapKeys() -> FunctionExpression {
        pipelineFunction("map_keys", [self])
    }

    public func mapValues() -> FunctionExpression {
        pipelineFunction("map_values", [self])
    }

    public func mapEntries() -> FunctionExpression {
        pipelineFunction("map_entries", [self])
    }

    public func cosineDistance(_ vector: VectorValue) -> FunctionExpression {
        FunctionExpression(expression: expression.cosineDistance(vector.vector))
    }

    public func cosineDistance(_ expression: Expression) -> FunctionExpression {
        pipelineFunction("cosine_distance", [self, expression])
    }

    public func cosineDistance(_ vector: [Double]) -> FunctionExpression {
        cosineDistance(VectorValue(vector))
    }

    public func dotProduct(_ vector: VectorValue) -> FunctionExpression {
        FunctionExpression(expression: expression.dotProduct(vector.vector))
    }

    public func dotProduct(_ expression: Expression) -> FunctionExpression {
        pipelineFunction("dot_product", [self, expression])
    }

    public func dotProduct(_ vector: [Double]) -> FunctionExpression {
        dotProduct(VectorValue(vector))
    }

    public func euclideanDistance(_ vector: VectorValue) -> FunctionExpression {
        FunctionExpression(expression: expression.euclideanDistance(vector.vector))
    }

    public func euclideanDistance(_ expression: Expression) -> FunctionExpression {
        pipelineFunction("euclidean_distance", [self, expression])
    }

    public func euclideanDistance(_ vector: [Double]) -> FunctionExpression {
        euclideanDistance(VectorValue(vector))
    }

    public func vectorLength() -> FunctionExpression {
        pipelineFunction("vector_length", [self])
    }

    public func count() -> AggregateFunction {
        AggregateFunction(aggregate: expression.count())
    }

    public func countDistinct() -> AggregateFunction {
        AggregateFunction(aggregate: expression.countDistinct())
    }

    public func sum() -> AggregateFunction {
        AggregateFunction(aggregate: expression.sum())
    }

    public func average() -> AggregateFunction {
        AggregateFunction(aggregate: expression.average())
    }

    public func minimum() -> AggregateFunction {
        AggregateFunction(aggregate: expression.minimum())
    }

    public func maximum() -> AggregateFunction {
        AggregateFunction(aggregate: expression.maximum())
    }

    public func first() -> AggregateFunction {
        AggregateFunction(functionName: "first", args: [self])
    }

    public func last() -> AggregateFunction {
        AggregateFunction(functionName: "last", args: [self])
    }

    public func arrayAgg() -> AggregateFunction {
        AggregateFunction(functionName: "array_agg", args: [self])
    }

    public func arrayAggDistinct() -> AggregateFunction {
        AggregateFunction(functionName: "array_agg_distinct", args: [self])
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("logicalMaximumExpressions")
    */
    public final func logicalMaximum(_ expressions: [Expression]) -> FunctionExpression {
        pipelineFunction("maximum", pipelineArguments(self, expressions.map { $0 as Any }))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("logicalMaximumValues")
    */
    public final func logicalMaximum(_ values: [Any]) -> FunctionExpression {
        pipelineFunction("maximum", pipelineArguments(self, values))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("logicalMinimumExpressions")
    */
    public final func logicalMinimum(_ expressions: [Expression]) -> FunctionExpression {
        pipelineFunction("minimum", pipelineArguments(self, expressions.map { $0 as Any }))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("logicalMinimumValues")
    */
    public final func logicalMinimum(_ values: [Any]) -> FunctionExpression {
        pipelineFunction("minimum", pipelineArguments(self, values))
    }

    public func unixMicrosToTimestamp() -> FunctionExpression {
        pipelineFunction("unix_micros_to_timestamp", [self])
    }

    public func timestampToUnixMicros() -> FunctionExpression {
        pipelineFunction("timestamp_to_unix_micros", [self])
    }

    public func unixMillisToTimestamp() -> FunctionExpression {
        pipelineFunction("unix_millis_to_timestamp", [self])
    }

    public func timestampToUnixMillis() -> FunctionExpression {
        pipelineFunction("timestamp_to_unix_millis", [self])
    }

    public func unixSecondsToTimestamp() -> FunctionExpression {
        pipelineFunction("unix_seconds_to_timestamp", [self])
    }

    public func timestampToUnixSeconds() -> FunctionExpression {
        pipelineFunction("timestamp_to_unix_seconds", [self])
    }

    public func timestampTruncate(granularity: TimeGranularity) -> FunctionExpression {
        pipelineFunction("timestamp_truncate", [self, granularity.rawValue])
    }

    public func timestampTruncate(granularity: Any) -> FunctionExpression {
        pipelineFunction("timestamp_truncate", [self, granularity])
    }

    public func timestampTruncate(granularity: TimeGranularity, timezone: Any) -> FunctionExpression {
        pipelineFunction("timestamp_truncate", [self, granularity.rawValue, timezone])
    }

    public func timestampTruncate(granularity: Any, timezone: Any) -> FunctionExpression {
        pipelineFunction("timestamp_truncate", [self, granularity, timezone])
    }

    public func timestampDiff(_ start: Expression, _ unit: TimeUnit) -> FunctionExpression {
        pipelineFunction("timestamp_diff", [self, start, unit.rawValue])
    }

    public func timestampDiff(_ start: Expression, _ unit: Any) -> FunctionExpression {
        pipelineFunction("timestamp_diff", [self, start, unit])
    }

    public func timestampExtract(part: TimePart) -> FunctionExpression {
        pipelineFunction("timestamp_extract", [self, part.rawValue])
    }

    public func timestampExtract(part: Any) -> FunctionExpression {
        pipelineFunction("timestamp_extract", [self, part])
    }

    public func timestampExtract(part: TimePart, timezone: Any) -> FunctionExpression {
        pipelineFunction("timestamp_extract", [self, part.rawValue, timezone])
    }

    public func timestampExtract(part: Any, timezone: Any) -> FunctionExpression {
        pipelineFunction("timestamp_extract", [self, part, timezone])
    }

    public func timestampAdd(_ amount: Int, _ unit: TimeUnit) -> FunctionExpression {
        pipelineFunction("timestamp_add", [self, amount, unit.rawValue])
    }

    public func timestampAdd(amount: Expression, unit: Any) -> FunctionExpression {
        pipelineFunction("timestamp_add", [self, amount, unit])
    }

    public func timestampSubtract(_ amount: Int, _ unit: TimeUnit) -> FunctionExpression {
        pipelineFunction("timestamp_subtract", [self, amount, unit.rawValue])
    }

    public func timestampSubtract(amount: Expression, unit: Any) -> FunctionExpression {
        pipelineFunction("timestamp_subtract", [self, amount, unit])
    }

    public func documentId() -> FunctionExpression {
        pipelineFunction("document_id", [self])
    }

    public func collectionId() -> FunctionExpression {
        pipelineFunction("collection_id", [self])
    }

    public func parent() -> FunctionExpression {
        pipelineFunction("parent", [self])
    }

    public func ifError(_ catchExpression: Expression) -> FunctionExpression {
        pipelineFunction("if_error", [self, catchExpression])
    }

    public func ifError(_ catchValue: Any) -> FunctionExpression {
        pipelineFunction("if_error", [self, catchValue])
    }

    public func ifAbsent(_ defaultValue: Any) -> FunctionExpression {
        pipelineFunction("if_absent", [self, defaultValue])
    }

    public func ifNull(_ defaultValue: Any) -> FunctionExpression {
        pipelineFunction("if_null", [self, defaultValue])
    }

    public func ifNull(_ defaultExpression: Expression) -> FunctionExpression {
        pipelineFunction("if_null", [self, defaultExpression])
    }

    public func coalesce(_ values: [Expression]) -> FunctionExpression {
        pipelineFunction("coalesce", pipelineArguments(self, values.map { $0 as Any }))
    }

    public func concat(_ values: [Any]) -> FunctionExpression {
        pipelineFunction("concat", pipelineArguments(self, values))
    }

    public func type() -> FunctionExpression {
        pipelineFunction("type", [self])
    }

    public func isType(_ type: String) -> BooleanExpression {
        pipelineBooleanFunction("is_type", [self, type])
    }
}

public class BooleanExpression: Expression {
    public let booleanExpression: com.google.firebase.firestore.pipeline.BooleanExpression

    public init(expression: com.google.firebase.firestore.pipeline.BooleanExpression) {
        self.booleanExpression = expression
        super.init(expression: expression)
    }

    public func not() -> BooleanExpression {
        BooleanExpression(expression: booleanExpression.not())
    }

    public func countIf() -> AggregateFunction {
        AggregateFunction(aggregate: booleanExpression.countIf())
    }

    public static func rawFunction(_ name: String, _ expressions: [Expression]) -> BooleanExpression {
        let args = expressions.map(\.expression).toList().toTypedArray()
        return BooleanExpression(expression: com.google.firebase.firestore.pipeline.BooleanExpression.rawFunction(name, *args))
    }
}

@available(*, deprecated, renamed: "BooleanExpression")
public typealias PipelineBooleanExpression = BooleanExpression

public extension BooleanExpression {
    @available(*, deprecated, renamed: "DocumentMatches.init(_:)")
    static func documentMatches(_ query: String) -> BooleanExpression {
        DocumentMatches(query)
    }

    @available(*, deprecated, message: "Use Field(field).equal(value) instead.")
    static func fieldEqualTo(_ field: String, value: Any) -> BooleanExpression {
        Field(field).equal(value)
    }

    @available(*, deprecated, message: "Use Field(field).arrayContainsAny(values) instead.")
    static func fieldArrayContainsAny(_ field: String, values: [Any]) -> BooleanExpression {
        Field(field).arrayContainsAny(values)
    }
}

public func and(_ lhs: BooleanExpression, _ rhs: BooleanExpression) -> BooleanExpression {
    BooleanExpression(expression: com.google.firebase.firestore.pipeline.Expression.and(lhs.booleanExpression, rhs.booleanExpression))
}

public func or(_ lhs: BooleanExpression, _ rhs: BooleanExpression) -> BooleanExpression {
    BooleanExpression(expression: com.google.firebase.firestore.pipeline.Expression.or(lhs.booleanExpression, rhs.booleanExpression))
}

public func xor(_ lhs: BooleanExpression, _ rhs: BooleanExpression) -> BooleanExpression {
    BooleanExpression(expression: com.google.firebase.firestore.pipeline.Expression.xor(lhs.booleanExpression, rhs.booleanExpression))
}

public func not(_ expression: BooleanExpression) -> BooleanExpression {
    expression.not()
}

public func nor(_ conditions: [BooleanExpression]) -> BooleanExpression {
    let first = conditions.first!
    let rest = conditions.dropFirst().map(\.booleanExpression).toList().toTypedArray()
    return BooleanExpression(expression: com.google.firebase.firestore.pipeline.Expression.nor(first.booleanExpression, *rest))
}

public class FunctionExpression: Expression {
    public init(functionName: String, args: [Expression], options: [String: Any]? = nil) {
        super.init(expression: pipelineRawFunctionExpression(functionName, args))
    }

    public override init(expression: com.google.firebase.firestore.pipeline.Expression) {
        super.init(expression: expression)
    }
}

public final class ArrayExpression: FunctionExpression {
    public init(_ elements: [Any]) {
        super.init(functionName: "array", args: elements.map { pipelineExpressionArgument($0) })
    }
}

public final class MapExpression: FunctionExpression {
    public init(_ elements: [String: Any]) {
        super.init(functionName: "map", args: pipelineMapExpressionArguments(elements))
    }
}

public final class ConditionalExpression: FunctionExpression {
    public init(_ expression: BooleanExpression, then thenExpression: Expression, else elseExpression: Expression) {
        super.init(functionName: "conditional", args: [expression, thenExpression, elseExpression])
    }
}

public func switchOn(_ condition: BooleanExpression, _ result: Expression, _ others: [Expression] = []) -> Expression {
    FunctionExpression(functionName: "switch_on", args: [condition, result] + others)
}

public final class CurrentTimestamp: FunctionExpression {
    public init() {
        super.init(functionName: "current_timestamp", args: [])
    }
}

public final class ErrorExpression: FunctionExpression {
    public init(_ errorMessage: String) {
        super.init(functionName: "error", args: [Constant(errorMessage)])
    }
}

public final class RandomExpression: FunctionExpression {
    public init() {
        super.init(functionName: "rand", args: [])
    }
}

public func rand() -> RandomExpression {
    RandomExpression()
}

public final class Constant: Expression {
    public init(_ value: Any?) {
        super.init(expression: pipelineConstantExpression(value))
    }

    public convenience init(_ value: Int) { self.init(value as Any) }
    public convenience init(_ value: Double) { self.init(value as Any) }
    public convenience init(_ value: String) { self.init(value as Any) }
    public convenience init(_ value: Bool) { self.init(value as Any) }
    public convenience init(_ value: Data) { self.init(value as Any) }
    public convenience init(_ value: GeoPoint) { self.init(value as Any) }
    public convenience init(_ value: Timestamp) { self.init(value as Any) }
    public convenience init(_ value: Date) { self.init(value as Any) }
    public convenience init(_ value: DocumentReference) { self.init(value as Any) }
    public convenience init(_ value: VectorValue) { self.init(value as Any) }

    public static let `nil` = Constant(nil as Any?)
}

public final class Field: Expression, Selectable {
    public let fieldName: String
    public var field: com.google.firebase.firestore.pipeline.Field {
        expression as! com.google.firebase.firestore.pipeline.Field
    }

    public init(_ name: String) {
        self.fieldName = name
        super.init(expression: com.google.firebase.firestore.pipeline.Expression.field(name))
    }

    public init(_ path: FieldPath) {
        self.fieldName = path.description
        super.init(expression: com.google.firebase.firestore.pipeline.Expression.field(path.fieldPath))
    }

    public var pipelineSelectable: com.google.firebase.firestore.pipeline.Selectable { self.field }
    public var pipelineExpression: Expression { self }
    public var pipelineAlias: String { fieldName }

    public func geoDistance(_ location: GeoPoint) -> Expression {
        Expression(expression: field.geoDistance(location.kotlin()))
    }

    public func matches(_ query: String) -> BooleanExpression {
        let args = [field, com.google.firebase.firestore.pipeline.Expression.constant(query)].toList().toTypedArray()
        return BooleanExpression(expression: com.google.firebase.firestore.pipeline.BooleanExpression.rawFunction("matches", *args))
    }
}

public final class Variable: Expression {
    public let name: String

    public init(_ name: String) {
        self.name = name
        super.init(expression: com.google.firebase.firestore.pipeline.Expression.variable(name))
    }
}

public final class CurrentDocument: Expression {
    public init() {
        super.init(expression: com.google.firebase.firestore.pipeline.Expression.currentDocument())
    }
}

public final class DocumentMatches: BooleanExpression {
    public init(_ query: String) {
        super.init(expression: com.google.firebase.firestore.pipeline.Expression.documentMatches(query))
    }
}

public final class Score: Expression {
    public init() {
        super.init(expression: com.google.firebase.firestore.pipeline.Expression.score())
    }
}

public final class AliasedExpression: Selectable {
    public let aliasedExpression: com.google.firebase.firestore.pipeline.AliasedExpression
    public let alias: String
    public let expr: Expression

    public init(_ expr: Expression, _ alias: String) {
        self.expr = expr
        self.alias = alias
        self.aliasedExpression = expr.expression.alias(alias)
    }

    public var pipelineSelectable: com.google.firebase.firestore.pipeline.Selectable { aliasedExpression }
    public var pipelineExpression: Expression { expr }
    public var pipelineAlias: String { alias }
}

public class AggregateFunction: KotlinConverting<com.google.firebase.firestore.pipeline.AggregateFunction> {
    public let aggregate: com.google.firebase.firestore.pipeline.AggregateFunction

    public init(aggregate: com.google.firebase.firestore.pipeline.AggregateFunction) {
        self.aggregate = aggregate
    }

    public init(functionName: String, args: [Expression]) {
        let platformArgs = args.map(\.expression).toList().toTypedArray()
        self.aggregate = com.google.firebase.firestore.pipeline.AggregateFunction.rawAggregate(functionName, *platformArgs)
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.pipeline.AggregateFunction {
        aggregate
    }

    public func `as`(_ name: String) -> AliasedAggregate {
        AliasedAggregate(aggregate: self, alias: name)
    }

    public static func count(_ fieldName: String) -> AggregateFunction {
        AggregateFunction(aggregate: com.google.firebase.firestore.pipeline.AggregateFunction.count(fieldName))
    }

    public static func sum(_ fieldName: String) -> AggregateFunction {
        AggregateFunction(aggregate: com.google.firebase.firestore.pipeline.AggregateFunction.sum(fieldName))
    }

    public static func average(_ fieldName: String) -> AggregateFunction {
        AggregateFunction(aggregate: com.google.firebase.firestore.pipeline.AggregateFunction.average(fieldName))
    }
}

public final class CountAll: AggregateFunction {
    public init() {
        super.init(aggregate: com.google.firebase.firestore.pipeline.AggregateFunction.countAll())
    }
}

public final class AliasedAggregate {
    public let aliasedAggregate: com.google.firebase.firestore.pipeline.AliasedAggregate
    public let aggregate: AggregateFunction
    public let alias: String

    public init(aggregate: AggregateFunction, alias: String) {
        self.aggregate = aggregate
        self.alias = alias
        self.aliasedAggregate = aggregate.aggregate.alias(alias)
    }
}

public struct Direction: Equatable, Hashable {
    public let rawValue: String

    public static let ascending = Direction(rawValue: "ascending")
    public static let descending = Direction(rawValue: "descending")
}

public struct Ordering {
    public let ordering: com.google.firebase.firestore.pipeline.Ordering
    public let expression: Expression
    public let direction: Direction

    public init(ordering: com.google.firebase.firestore.pipeline.Ordering) {
        self.ordering = ordering
        self.expression = Expression(expression: ordering.expr)
        self.direction = ordering.dir == com.google.firebase.firestore.pipeline.Ordering.Direction.ASCENDING ? .ascending : .descending
    }

    public init(expression: Expression, direction: Direction) {
        self.expression = expression
        self.direction = direction
        self.ordering = direction == .descending
            ? com.google.firebase.firestore.pipeline.Ordering.descending(expression.expression)
            : com.google.firebase.firestore.pipeline.Ordering.ascending(expression.expression)
    }
}

public struct DistanceMeasure: Equatable, Hashable {
    public let measure: com.google.firebase.firestore.pipeline.FindNearestStage.DistanceMeasure
    public let rawValue: String

    public static let euclidean = DistanceMeasure(measure: com.google.firebase.firestore.pipeline.FindNearestStage.DistanceMeasure.EUCLIDEAN, rawValue: "euclidean")
    public static let cosine = DistanceMeasure(measure: com.google.firebase.firestore.pipeline.FindNearestStage.DistanceMeasure.COSINE, rawValue: "cosine")
    public static let dotProduct = DistanceMeasure(measure: com.google.firebase.firestore.pipeline.FindNearestStage.DistanceMeasure.DOT_PRODUCT, rawValue: "dot_product")
}

public struct TimeUnit: Equatable, Hashable {
    public let rawValue: String

    public static let microsecond = TimeUnit(rawValue: "microsecond")
    public static let millisecond = TimeUnit(rawValue: "millisecond")
    public static let second = TimeUnit(rawValue: "second")
    public static let minute = TimeUnit(rawValue: "minute")
    public static let hour = TimeUnit(rawValue: "hour")
    public static let day = TimeUnit(rawValue: "day")
}

public struct TimePart: Equatable, Hashable {
    public let rawValue: String

    public static let microsecond = TimePart(rawValue: "microsecond")
    public static let millisecond = TimePart(rawValue: "millisecond")
    public static let second = TimePart(rawValue: "second")
    public static let minute = TimePart(rawValue: "minute")
    public static let hour = TimePart(rawValue: "hour")
    public static let dayOfWeek = TimePart(rawValue: "dayofweek")
    public static let day = TimePart(rawValue: "day")
    public static let dayOfYear = TimePart(rawValue: "dayofyear")
    public static let week = TimePart(rawValue: "week")
    public static let weekMonday = TimePart(rawValue: "week(monday)")
    public static let weekTuesday = TimePart(rawValue: "week(tuesday)")
    public static let weekWednesday = TimePart(rawValue: "week(wednesday)")
    public static let weekThursday = TimePart(rawValue: "week(thursday)")
    public static let weekFriday = TimePart(rawValue: "week(friday)")
    public static let weekSaturday = TimePart(rawValue: "week(saturday)")
    public static let weekSunday = TimePart(rawValue: "week(sunday)")
    public static let isoweek = TimePart(rawValue: "isoweek")
    public static let month = TimePart(rawValue: "month")
    public static let quarter = TimePart(rawValue: "quarter")
    public static let year = TimePart(rawValue: "year")
    public static let isoyear = TimePart(rawValue: "isoyear")
}

public struct TimeGranularity: Equatable, Hashable {
    public let rawValue: String

    public static let microsecond = TimeGranularity(rawValue: "microsecond")
    public static let millisecond = TimeGranularity(rawValue: "millisecond")
    public static let second = TimeGranularity(rawValue: "second")
    public static let minute = TimeGranularity(rawValue: "minute")
    public static let hour = TimeGranularity(rawValue: "hour")
    public static let day = TimeGranularity(rawValue: "day")
    public static let week = TimeGranularity(rawValue: "week")
    public static let weekMonday = TimeGranularity(rawValue: "week(monday)")
    public static let weekTuesday = TimeGranularity(rawValue: "week(tuesday)")
    public static let weekWednesday = TimeGranularity(rawValue: "week(wednesday)")
    public static let weekThursday = TimeGranularity(rawValue: "week(thursday)")
    public static let weekFriday = TimeGranularity(rawValue: "week(friday)")
    public static let weekSaturday = TimeGranularity(rawValue: "week(saturday)")
    public static let weekSunday = TimeGranularity(rawValue: "week(sunday)")
    public static let isoweek = TimeGranularity(rawValue: "isoweek")
    public static let month = TimeGranularity(rawValue: "month")
    public static let quarter = TimeGranularity(rawValue: "quarter")
    public static let year = TimeGranularity(rawValue: "year")
    public static let isoyear = TimeGranularity(rawValue: "isoyear")
}

public struct PipelineSource {
    public let source: com.google.firebase.firestore.PipelineSource
    private let firestore: com.google.firebase.firestore.FirebaseFirestore?

    public init(source: com.google.firebase.firestore.PipelineSource, firestore: com.google.firebase.firestore.FirebaseFirestore? = nil) {
        self.source = source
        self.firestore = firestore
    }

    public func collection(_ path: String, forceIndex: String? = nil) -> Pipeline {
        if let forceIndex {
            guard let firestore else {
                return Pipeline(pipeline: source.collection(path), errorMessage: "collection(_:forceIndex:) requires a Firestore-backed PipelineSource.")
            }
            return collection(CollectionReference(ref: firestore.collection(path)), forceIndex: forceIndex)
        }
        return Pipeline(pipeline: source.collection(path))
    }

    public func collection(_ coll: CollectionReference, forceIndex: String? = nil) -> Pipeline {
        guard let forceIndex else {
            return Pipeline(pipeline: source.collection(coll.ref))
        }
        let hints = com.google.firebase.firestore.pipeline.CollectionHints().withForceIndex(forceIndex)
        let options = com.google.firebase.firestore.pipeline.CollectionSourceOptions().withHints(hints)
        return Pipeline(pipeline: source.collection(coll.ref, options))
    }

    public func collectionGroup(_ collectionId: String, forceIndex: String? = nil) -> Pipeline {
        guard let forceIndex else {
            return Pipeline(pipeline: source.collectionGroup(collectionId))
        }
        let hints = com.google.firebase.firestore.pipeline.CollectionHints().withForceIndex(forceIndex)
        let options = com.google.firebase.firestore.pipeline.CollectionGroupOptions().withHints(hints)
        return Pipeline(pipeline: source.collectionGroup(collectionId, options))
    }

    public func database() -> Pipeline {
        Pipeline(pipeline: source.database())
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("documentsReferences")
    */
    public func documents(_ docs: [DocumentReference]) -> Pipeline {
        let refs = docs.map(\.ref).toList().toTypedArray()
        return Pipeline(pipeline: source.documents(*refs))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("documentsPaths")
    */
    public func documents(_ paths: [String]) -> Pipeline {
        let platformPaths = paths.toList().toTypedArray()
        return Pipeline(pipeline: source.documents(*platformPaths))
    }

    public func create(from query: Query) -> Pipeline {
        Pipeline(pipeline: source.createFrom(query.query))
    }
}

public class Pipeline: KotlinConverting<com.google.firebase.firestore.Pipeline> {
    public let pipeline: com.google.firebase.firestore.Pipeline
    private let errorMessage: String?

    public init(pipeline: com.google.firebase.firestore.Pipeline, errorMessage: String? = nil) {
        self.pipeline = pipeline
        self.errorMessage = errorMessage
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.Pipeline {
        pipeline
    }

    private func next(_ nextPipeline: com.google.firebase.firestore.Pipeline) -> Pipeline {
        Pipeline(pipeline: nextPipeline, errorMessage: errorMessage)
    }

    private func failing(_ message: String) -> Pipeline {
        let combined = errorMessage == nil ? message : "\(errorMessage!)\n\(message)"
        return Pipeline(pipeline: pipeline, errorMessage: combined)
    }

    public struct Snapshot {
        public let snapshot: com.google.firebase.firestore.Pipeline.Snapshot
        public let executionTime: Timestamp
        public let results: [PipelineResult]

        public init(snapshot: com.google.firebase.firestore.Pipeline.Snapshot) {
            self.snapshot = snapshot
            self.executionTime = Timestamp(timestamp: snapshot.executionTime)
            self.results = Array(snapshot.results.map { PipelineResult(result: $0) })
        }
    }

    public func execute() async throws -> Pipeline.Snapshot {
        if let errorMessage {
            throw pipelineInvalidArgumentError(errorMessage)
        }
        do {
            return Pipeline.Snapshot(snapshot: try pipeline.execute().await())
        } catch is com.google.firebase.firestore.FirebaseFirestoreException {
            throw asNSError(firestoreException: error)
        } catch is java.lang.IllegalArgumentException {
            throw pipelineInvalidArgumentError(error.message ?? "Invalid Firestore Pipeline")
        }
    }

    public func addFields(_ selectables: [Selectable]) -> Pipeline {
        guard let first = selectables.first else { return failing("addFields requires at least one selectable.") }
        if let duplicate = duplicateSelectableAliasMessage(selectables) { return failing(duplicate) }
        let rest = selectables.dropFirst().map(\.pipelineSelectable).toList().toTypedArray()
        return next(pipeline.addFields(first.pipelineSelectable, *rest))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("removePipelineFields")
    */
    public final func removeFields(_ fields: [Field]) -> Pipeline {
        guard let first = fields.first else { return failing("removeFields requires at least one field.") }
        let rest = fields.dropFirst().map(\.field).toList().toTypedArray()
        return next(pipeline.removeFields(first.field, *rest))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("removeFieldNames")
    */
    public final func removeFields(_ fields: [String]) -> Pipeline {
        guard let first = fields.first else { return failing("removeFields requires at least one field.") }
        let rest = fields.dropFirst().toList().toTypedArray()
        return next(pipeline.removeFields(first, *rest))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("selectPipelineSelectables")
    */
    public final func select(_ selections: [Selectable]) -> Pipeline {
        guard let first = selections.first else { return failing("select requires at least one selectable.") }
        if let duplicate = duplicateSelectableAliasMessage(selections) { return failing(duplicate) }
        let rest = selections.dropFirst().map { $0.pipelineSelectable as Any }.toList().toTypedArray()
        return next(pipeline.select(first.pipelineSelectable, *rest))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("selectFieldNames")
    */
    public final func select(_ selections: [String]) -> Pipeline {
        guard let first = selections.first else { return failing("select requires at least one field.") }
        let rest = selections.dropFirst().map { $0 as Any }.toList().toTypedArray()
        return next(pipeline.select(first, *rest))
    }

    public func `where`(_ condition: BooleanExpression) -> Pipeline {
        next(pipeline.where(condition.booleanExpression))
    }

    @available(*, deprecated, renamed: "where(_:)")
    public func whereCondition(_ condition: BooleanExpression) -> Pipeline {
        self.`where`(condition)
    }

    public func offset(_ offset: Int32) -> Pipeline {
        next(pipeline.offset(Int(offset)))
    }

    public func limit(_ limit: Int32) -> Pipeline {
        next(pipeline.limit(Int(limit)))
    }

    public func define(_ variables: [AliasedExpression]) -> Pipeline {
        guard let first = variables.first else { return failing("define requires at least one variable.") }
        let selectables = variables.map { $0 as Selectable }
        if let duplicate = duplicateSelectableAliasMessage(selectables) { return failing(duplicate) }
        let rest = variables.dropFirst().map(\.aliasedExpression).toList().toTypedArray()
        return next(pipeline.define(first.aliasedExpression, *rest))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("distinctFieldNames")
    */
    public final func distinct(_ groups: [String]) -> Pipeline {
        guard let first = groups.first else { return failing("distinct requires at least one group.") }
        let rest = groups.dropFirst().map { $0 as Any }.toList().toTypedArray()
        return next(pipeline.distinct(first, *rest))
    }

    /* SKIP INSERT:
    @kotlin.jvm.JvmName("distinctPipelineSelectables")
    */
    public final func distinct(_ groups: [Selectable]) -> Pipeline {
        guard let first = groups.first else { return failing("distinct requires at least one group.") }
        if let duplicate = duplicateSelectableAliasMessage(groups) { return failing(duplicate) }
        let rest = groups.dropFirst().map { $0.pipelineSelectable as Any }.toList().toTypedArray()
        return next(pipeline.distinct(first.pipelineSelectable, *rest))
    }

    public func aggregate(_ aggregates: [AliasedAggregate], groups: [Selectable]? = nil) -> Pipeline {
        guard let first = aggregates.first else { return failing("aggregate requires at least one accumulator.") }
        if let duplicate = duplicateAggregateAliasMessage(aggregates) { return failing(duplicate) }
        if let groups, !groups.isEmpty {
            let platformGroups = groups.map(\.pipelineSelectable).toList().toTypedArray()
            let stage = com.google.firebase.firestore.pipeline.AggregateStage.withAccumulators(first.aliasedAggregate, *aggregates.dropFirst().map(\.aliasedAggregate).toList().toTypedArray()).withGroups(platformGroups[0], *platformGroups.drop(1).toList().toTypedArray())
            return next(pipeline.aggregate(stage))
        }
        let rest = aggregates.dropFirst().map(\.aliasedAggregate).toList().toTypedArray()
        return next(pipeline.aggregate(first.aliasedAggregate, *rest))
    }

    public func findNearest(field: Field, vectorValue: VectorValue, distanceMeasure: DistanceMeasure, limit: Int? = nil, distanceField: String? = nil) -> Pipeline {
        var options = com.google.firebase.firestore.pipeline.FindNearestOptions()
        if let limit { options = options.withLimit(Int64(limit)) }
        if let distanceField, let nextOptions = options.withDistanceField(distanceField) {
            options = nextOptions
        }
        let vectorExpression = com.google.firebase.firestore.pipeline.Expression.vector(vectorValue.vector)
        return next(pipeline.findNearest(field.fieldName, vectorExpression, distanceMeasure.measure, options))
    }

    public func sort(_ orderings: [Ordering]) -> Pipeline {
        guard let first = orderings.first else { return failing("sort requires at least one ordering.") }
        let rest = orderings.dropFirst().map(\.ordering).toList().toTypedArray()
        return next(pipeline.sort(first.ordering, *rest))
    }

    public func replace(with expression: Expression) -> Pipeline {
        next(pipeline.replaceWith(expression.expression))
    }

    public func replace(with fieldName: String) -> Pipeline {
        next(pipeline.replaceWith(fieldName))
    }

    public func sample(count: Int64) -> Pipeline {
        next(pipeline.sample(com.google.firebase.firestore.pipeline.SampleStage.withDocLimit(Int(count))))
    }

    public func sample(percentage: Double) -> Pipeline {
        next(pipeline.sample(com.google.firebase.firestore.pipeline.SampleStage.withPercentage(percentage)))
    }

    public func search(query: Expression, languageCode: String? = nil, retrievalDepth: Int? = nil, sort: [Ordering]? = nil, offset: Int? = nil, limit: Int? = nil, addFields: [Selectable]? = nil) -> Pipeline {
        let boolQuery = (query as? BooleanExpression)?.booleanExpression ?? query.asBoolean().booleanExpression
        var stage = com.google.firebase.firestore.pipeline.SearchStage.withQuery(boolQuery)
        if let languageCode { stage = stage.withLanguageCode(languageCode) }
        if let retrievalDepth { stage = stage.withRetrievalDepth(Int64(retrievalDepth)) }
        if let offset { stage = stage.withOffset(Int64(offset)) }
        if let limit { stage = stage.withLimit(Int64(limit)) }
        if let sort, let first = sort.first {
            let rest = sort.dropFirst().map(\.ordering).toList().toTypedArray()
            stage = stage.withSort(first.ordering, *rest)
        }
        if let addFields, let first = addFields.first {
            if let duplicate = duplicateSelectableAliasMessage(addFields) { return failing(duplicate) }
            let rest = addFields.dropFirst().map(\.pipelineSelectable).toList().toTypedArray()
            stage = stage.withAddFields(first.pipelineSelectable, *rest)
        }
        return next(pipeline.search(stage))
    }

    public func search(query: String, languageCode: String? = nil, retrievalDepth: Int? = nil, sort: [Ordering]? = nil, offset: Int? = nil, limit: Int? = nil, addFields: [Selectable]? = nil) -> Pipeline {
        search(query: DocumentMatches(query), languageCode: languageCode, retrievalDepth: retrievalDepth, sort: sort, offset: offset, limit: limit, addFields: addFields)
    }

    public func union(with other: Pipeline) -> Pipeline {
        if let otherError = other.errorMessage { return failing(otherError) }
        return next(pipeline.union(other.pipeline))
    }

    public func unnest(_ field: Selectable, indexField: String? = nil) -> Pipeline {
        guard let indexField else {
            return next(pipeline.unnest(field.pipelineSelectable))
        }
        let options = com.google.firebase.firestore.pipeline.UnnestOptions().withIndexField(indexField)
        return next(pipeline.unnest(field.pipelineSelectable, options))
    }

    public func rawStage(name: String, params: [Any], options: [String: Any]? = nil) -> Pipeline {
        let args = params.map { pipelineRawValueNonNil($0) }.toList().toTypedArray()
        var stage = com.google.firebase.firestore.pipeline.RawStage.ofName(name).withArguments(*args)
        if let options {
            for (key, value) in options {
                if let str = value as? String {
                    stage = stage.withOption(key, str)
                } else if let bool = value as? Bool {
                    stage = stage.withOption(key, bool)
                } else if let int = value as? Int {
                    stage = stage.withOption(key, Int64(int))
                } else if let int64 = value as? Int64 {
                    stage = stage.withOption(key, int64)
                } else if let double = value as? Double {
                    stage = stage.withOption(key, double)
                } else if let field = value as? Field {
                    stage = stage.withOption(key, field.field)
                }
            }
        }
        return next(pipeline.rawStage(stage))
    }

    public func toArrayExpression() -> Expression {
        Expression(expression: pipeline.toArrayExpression())
    }

    public func toScalarExpression() -> Expression {
        Expression(expression: pipeline.toScalarExpression())
    }
}

@available(*, deprecated, renamed: "Pipeline.Snapshot")
public typealias PipelineSnapshot = Pipeline.Snapshot

public class Subcollection: Pipeline {
    public init(_ path: String) {
        super.init(pipeline: com.google.firebase.firestore.PipelineSource.subcollection(path))
    }
}

public final class PipelineResult: KotlinConverting<com.google.firebase.firestore.PipelineResult> {
    public let result: com.google.firebase.firestore.PipelineResult

    public init(result: com.google.firebase.firestore.PipelineResult) {
        self.result = result
    }

    // SKIP @nooverride
    public override func kotlin(nocopy: Bool = false) -> com.google.firebase.firestore.PipelineResult {
        result
    }

    public var ref: DocumentReference? {
        guard let ref = result.ref else { return nil }
        return DocumentReference(ref: ref)
    }

    public var id: String? {
        result.getId()
    }

    public var createTime: Timestamp? {
        guard let timestamp = result.createTime else { return nil }
        return Timestamp(timestamp: timestamp)
    }

    public var updateTime: Timestamp? {
        guard let timestamp = result.updateTime else { return nil }
        return Timestamp(timestamp: timestamp)
    }

    public var data: [String: Any?] {
        firestoreDeepSwiftNullable(map: result.getData())
    }

    @available(*, deprecated, message: "Use the null-preserving data property instead.")
    public func data() -> [String: Any] {
        var dict = [String: Any]()
        for (key, value) in data {
            if let value {
                dict[key] = value
            }
        }
        return dict
    }

    public func get(_ fieldName: String) -> Any? {
        firestoreDeepSwift(value: result.get(fieldName))
    }

    public func get(_ fieldPath: FieldPath) -> Any? {
        firestoreDeepSwift(value: result.get(fieldPath.fieldPath))
    }

    public func get(_ field: Field) -> Any? {
        firestoreDeepSwift(value: result.get(field.fieldName))
    }
}

public class FieldValue {
    public class func arrayRemove(_ elements: [Any]) -> com.google.firebase.firestore.FieldValue {
        let elementsArray = elements.map({ $0.kotlin() }).toList().toTypedArray()
        return com.google.firebase.firestore.FieldValue.arrayRemove(*elementsArray)
    }

    public class func arrayUnion(_ elements: [Any]) -> com.google.firebase.firestore.FieldValue {
        let elementsArray = elements.map({ $0.kotlin() }).toList().toTypedArray()
        return com.google.firebase.firestore.FieldValue.arrayUnion(*elementsArray)
    }

    public class func delete() -> com.google.firebase.firestore.FieldValue {
        return com.google.firebase.firestore.FieldValue.delete()
    }

    public class func increment(_ d: Double) -> com.google.firebase.firestore.FieldValue {
        return com.google.firebase.firestore.FieldValue.increment(d)
    }

    public class func increment(_ l: Int64) -> com.google.firebase.firestore.FieldValue {
        return com.google.firebase.firestore.FieldValue.increment(l)
    }

    public class func serverTimestamp() -> com.google.firebase.firestore.FieldValue {
        return com.google.firebase.firestore.FieldValue.serverTimestamp()
    }

    public class func vector(_ array: [Double]) -> VectorValue {
        return VectorValue(array)
    }

    public class func vector(_ array: [Float]) -> VectorValue {
        return VectorValue(array.map { Double($0) })
    }
}

// MARK: Errors

public enum FirestoreErrorCode: Int {
    case OK = 0
    case cancelled = 1
    case unknown = 2
    case invalidArgument = 3
    case deadlineExceeded = 4
    case notFound = 5
    case alreadyExists = 6
    case permissionDenied = 7
    case resourceExhausted = 8
    case failedPrecondition = 9
    case aborted = 10
    case outOfRange = 11
    case unimplemented = 12
    case `internal` = 13
    case unavailable = 14
    case dataLoss = 15
    case unauthenticated = 16
}

public let FirestoreErrorDomain = "FIRFirestoreErrorDomain"

fileprivate func asNSError(firestoreException: com.google.firebase.firestore.FirebaseFirestoreException) -> Error {
    let userInfo: [String: Any] = [:]
    if let detailMessage = firestoreException.message {
        userInfo[NSLocalizedFailureReasonErrorKey] = detailMessage
    }
    return NSError(domain: FirestoreErrorDomain, code: firestoreException.code.value(), userInfo: userInfo)
}

// MARK: - Codable support

/// Encodes a `Codable` value into a `[String: Any]` Firestore document map.
/// `Timestamp` and `GeoPoint` fields are preserved as native Firestore types.
/// Note: use `Timestamp` (not `Date`) in your model for Firestore timestamp fields.
public class FirestoreEncoder {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            var container = enc.container(keyedBy: _FirestoreDateSentinelKeys.self)
            try container.encode(date.timeIntervalSince1970, forKey: .marker)
        }
        let data = try encoder.encode(value)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.invalidArgument.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "Top-level encoded value must be a dictionary"])
        }
        var result = restoreFirestoreTypes(dict) as! [String: Any]
        /* SKIP INSERT:
        for (field in value.javaClass.declaredFields) {
            if (field.isAnnotationPresent(ServerTimestamp::class.java)) {
                field.isAccessible = true
                val fieldVal = try { field.get(value) } catch (e: Exception) { null }
                if (fieldVal == null) {
                    result[field.name] = com.google.firebase.firestore.FieldValue.serverTimestamp()
                }
            }
        }
        */
        return result
    }

    private func restoreFirestoreTypes(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            // @ServerTimestamp nil sentinel → FieldValue.serverTimestamp()
            if dict.count == 1, let _ = dict["__fts_server__"] {
                return com.google.firebase.firestore.FieldValue.serverTimestamp()
            }
            // Date sentinel → Timestamp
            if dict.count == 1, let t = dict["__firestore_date__"] {
                let interval = coerceDouble(t) ?? 0.0
                return Timestamp(date: Date(timeIntervalSince1970: interval))
            }
            // Timestamp sentinel → Timestamp
            if dict.count == 2, let s = dict["__fts__"], let n = dict["__ftn__"] {
                let seconds = coerceInt64(s) ?? Int64(0)
                let nanos = coerceInt32(n) ?? Int32(0)
                return Timestamp(seconds: seconds, nanoseconds: nanos)
            }
            // GeoPoint sentinel → GeoPoint
            if dict.count == 2, let lat = dict["__fgp_lat__"], let lng = dict["__fgp_lng__"] {
                return GeoPoint(latitude: coerceDouble(lat) ?? 0.0, longitude: coerceDouble(lng) ?? 0.0)
            }
            // VectorValue sentinel → VectorValue
            if dict.count == 1, let values = dict["__fvv_array__"] as? [Any] {
                return VectorValue(values.compactMap { coerceDouble($0) })
            }
            var result = [String: Any]()
            for (key, val) in dict {
                result[key] = restoreFirestoreTypes(val)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { restoreFirestoreTypes($0) }
        }
        return value
    }
}

private enum _FirestoreDateSentinelKeys: String, CodingKey {
    case marker = "__firestore_date__"
}

/// Decodes a `Codable` value from a `[String: Any]` Firestore document map.
/// `Timestamp` fields decode as either `Timestamp` or `Date` (via `.secondsSince1970`).
/// Pass `documentID` to populate `@DocumentID`-annotated properties.
public class FirestoreDecoder {
    public init() {}

    // SKIP DECLARE: public inline fun <reified T : Decodable> decode(from: Dictionary<String, Any>): T
    public func decode<T: Decodable>(from data: [String: Any]) throws -> T {
        return try decode(from: data, documentID: nil)
    }

    // SKIP DECLARE: public inline fun <reified T : Decodable> decode(from: Dictionary<String, Any>, documentID: String?): T
    public func decode<T: Decodable>(from data: [String: Any], documentID: String?) throws -> T {
        var prepared = prepareForJSON(data) as! [String: Any]
        if let id = documentID {
            prepared["__document_id__"] = id
        }
        let jsonData = try JSONSerialization.data(withJSONObject: prepared)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let id = documentID {
            // SKIP REPLACE: decoder.userInfo[CodingUserInfoKey(rawValue = "__firestore_document_id_key__")!!] = id
            decoder.userInfo[CodingUserInfoKey.firestoreDocumentID] = id
        }
        /* SKIP INSERT:
        val result = decoder.decode(T::class, from = jsonData)
        if (documentID != null) {
            for (field in result.javaClass.declaredFields) {
                if (field.isAnnotationPresent(DocumentID::class.java)) {
                    field.isAccessible = true
                    try { field.set(result, documentID) } catch (e: Exception) { }
                }
            }
        }
        return result
        */
        // SKIP REPLACE:
        return try decoder.decode(T.self, from: jsonData)
    }

    public func prepareForJSON(_ value: Any?) -> Any {
        guard let value = value else { return NSNull() }
        // Convert Timestamp to timeInterval Double so both Date and Timestamp fields decode correctly.
        // Timestamp.init(from:) handles Double via its singleValueContainer path.
        if let ts = value as? Timestamp {
            return ts.seconds + Double(ts.nanoseconds) / 1_000_000_000.0
        }
        if let gp = value as? GeoPoint {
            return ["__fgp_lat__": gp.latitude, "__fgp_lng__": gp.longitude]
        }
        if let vector = value as? VectorValue {
            return ["__fvv_array__": vector.array]
        }
        if let dict = value as? [String: Any] {
            var result = [String: Any]()
            for (key, val) in dict {
                result[key] = prepareForJSON(val)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { prepareForJSON($0) }
        }
        return value
    }
}

// MARK: - JSON numeric coercion helpers

fileprivate func coerceInt64(_ v: Any) -> Int64? {
    if let x = v as? Int64 { return x }
    if let x = v as? Int { return Int64(x) }
    if let x = v as? Int32 { return Int64(x) }
    if let x = v as? Double { return Int64(x) }
    return nil
}

fileprivate func coerceInt32(_ v: Any) -> Int32? {
    if let x = v as? Int32 { return x }
    if let x = v as? Int64 { return Int32(x) }
    if let x = v as? Int { return Int32(x) }
    if let x = v as? Double { return Int32(x) }
    return nil
}

fileprivate func coerceDouble(_ v: Any) -> Double? {
    if let x = v as? Double { return x }
    if let x = v as? Int64 { return Double(x) }
    if let x = v as? Int { return Double(x) }
    return nil
}

#endif
#endif

#if SKIP_BRIDGE
// The generated GeoPoint bridge class declares Codable but cannot auto-synthesize it
// (JObject peer is not Codable, and encode/decode methods are not JNI-bridgeable).
// This extension satisfies the Codable conformance using the JNI-bridged properties.
extension GeoPoint {
    private enum CodingKeys: String, CodingKey {
        case latitude = "__fgp_lat__"
        case longitude = "__fgp_lng__"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
    }

    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lat = try container.decode(Double.self, forKey: .latitude)
        let lng = try container.decode(Double.self, forKey: .longitude)
        self.init(latitude: lat, longitude: lng)
    }
}
#endif
