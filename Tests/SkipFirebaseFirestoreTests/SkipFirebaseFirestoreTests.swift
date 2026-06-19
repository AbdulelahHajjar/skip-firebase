// Copyright 2024–2026 Skip
// SPDX-License-Identifier: MPL-2.0
import XCTest
import OSLog
import Foundation

import SkipFirebaseCore
import SkipFirebaseFirestore
private typealias FirestorePipelineExpression = Expression

let logger: Logger = Logger(subsystem: "SkipFirebaseFirestoreTests", category: "Tests")

/// True when running in a transpiled Java runtime environment
let isJava = ProcessInfo.processInfo.environment["java.io.tmpdir"] != nil
/// True when running within an Android environment (either an emulator or device)
let isAndroid = isJava && ProcessInfo.processInfo.environment["ANDROID_ROOT"] != nil
/// True is the transpiled code is currently running in the local Robolectric test environment
let isRobolectric = isJava && !isAndroid
/// True if the system's `Int` type is 32-bit.
let is32BitInteger = Int64(Int.max) == Int64(Int32.max)

let appName: String = "SkipFirebaseDemo"

// NOTE: we have @MainActor on SkipFirebaseFirestoreTests to force non-concurrent test execution in order to avoid errors like this:
//
// Test Suite 'Selected tests' started at 2024-11-07 12:54:30.612.Test Suite 'skip-firebasePackageTests.xctest' started at 2024-11-07 12:54:30.614.Test Suite 'SkipFirebaseFirestoreTests' started at 2024-11-07 12:54:30.614.Test Case '-[SkipFirebaseFirestoreTests.SkipFirebaseFirestoreTests test_exists_trueForExistentDocument]' started.2024-11-07 12:54:30.823 xctest[15414:52946] *** Assertion failure in void firebase::firestore::core::FirestoreClient::Initialize(const User &, const Settings &)(), /var/folders/4b/7k50gk0j4f5bjk3799wdt8nw0000gn/T/ZipRelease/2024-10-14T13-23-42/project-macos/Pods/FirebaseFirestoreInternal/Firestore/core/src/core/firestore_client.cc:2172024-11-07 12:54:30.900 xctest[15414:52946] *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'FIRESTORE INTERNAL ASSERTION FAILED: Failed to open DB: Internal: Failed to open LevelDB database at /Users/runner/Library/Application Support/firestore/SkipFirebaseDemo/skip-firebase-demo/main: LevelDB error: IO error: lock /Users/runner/Library/Application Support/firestore/SkipFirebaseDemo/skip-firebase-demo/main/LOCK: Resource temporarily unavailable (expected created.ok())'


@MainActor final class SkipFirebaseFirestoreTests: XCTestCase {

    /// App needs to be initialized in setUp and cleaned up in tearDown.
    ///
    /// The class is `@MainActor` (to serialize test execution), which makes these static
    /// properties main-actor-isolated — and thus a hard error under Swift 6 to access from
    /// XCTest's `setUp()` (nonisolated on some SDKs) or to send into nonisolated Firebase
    /// async methods. `nonisolated(unsafe)` opts them out of isolation checking; safe because
    /// `@MainActor` already serializes all access. (Stripped by the transpiler for Kotlin,
    /// which has no actor isolation.)
    nonisolated(unsafe) fileprivate static var app: FirebaseApp?
    nonisolated(unsafe) fileprivate static var db: Firestore?

    // runtestFirestoreBundles$SkipFirebaseFirestore_debugUnitTest kotlinx.coroutines.test.UncompletedCoroutinesError: After waiting for 10s, the test coroutine is not completing, there were active child jobs: [DispatchedCoroutine{Active}@3816ef2f]
    // Suppressed: org.robolectric.android.internal.AndroidTestEnvironment$UnExecutedRunnablesException: Main looper has queued unexecuted runnables. This might be the cause of the test failure. You might need a shadowOf(Looper.getMainLooper()).idle() call

    var app: FirebaseApp { Self.app! }
    var db: Firestore { Self.db! }

    override func setUp() {
        if Self.app != nil {
            return
        }

        // this is generally loaded from the system's GoogleService-Info.plist / google-services.json using the default constructor, but for the sake of the test case we manually set it up here
        let options = FirebaseOptions(googleAppID: "1:599015466373:ios:918f07f9e07f56b03890ec", gcmSenderID: "599015466373")

        XCTAssertNil(options.apiKey)
        XCTAssertNil(options.projectID)
        XCTAssertNil(options.storageBucket)
        XCTAssertNil(options.databaseURL)
        #if !SKIP // TODO: add options to FirebaseOptions
        XCTAssertNil(options.appGroupID)
        XCTAssertNil(options.clientID)
        #endif

        options.projectID = "skip-firebase-demo"
        options.storageBucket = "skip-firebase-demo.appspot.com"

        options.apiKey = ProcessInfo.processInfo.environment["SKIP_FIREBASE_API_KEY"] ?? String(data: Data(base64Encoded: "QUl6YVN5QzV2bDFNYUc2S0hMOU15V1kyWGhxTHZCdVJsVEhrc3lR")!, encoding: .utf8)
        if options.apiKey == nil {
            fatalError("no api key set in SKIP_FIREBASE_API_KEY environment")
        }

        if ({ 0 == 1 }())  {
            // these are just to validate the existance of the API
            FirebaseApp.configure()
            FirebaseApp.configure(options: options)
        }

        FirebaseApp.configure(name: appName, options: options)

        // the app is registered statically, so check to see if it has been registered
        if let app = FirebaseApp.app(name: appName) {
            app.isDataCollectionDefaultEnabled = false
            Self.app = app
            Self.db = Firestore.firestore(app: app, database: "(default)")
        } else {
            fatalError("unable to load FirebaseApp.app(name: \"\(appName)\")")
        }
    }

    #if SKIP
    override func tearDown() throws {
        //FirebaseApp.app(name: appName)?.delete()

        // needed or else: Suppressed: org.robolectric.android.internal.AndroidTestEnvironment$UnExecutedRunnablesException: Main looper has queued unexecuted runnables. This might be the cause of the test failure. You might need a shadowOf(Looper.getMainLooper()).idle() call.
        //org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()
    }
    #else
    override func tearDown() async throws {
        //await FirebaseApp.app(name: appName)?.delete()
    }
    #endif

    /// This is never invoked, it is just to validate API parity
    private func validateFirebaseWrapperAPI() async throws {
        //let db: Firestore = Firestore.firestore(app: self.app)

        let cityDocumentFromRoot = db.document("cities/nyc")
        XCTAssertEqual(cityDocumentFromRoot.documentID, "nyc")

        let colRef: CollectionReference = db.collection("")
        let _: Firestore = colRef.firestore
        let _: String = colRef.collectionID
        let dref: DocumentReference? = colRef.parent
        let _ = dref?.path
        let _ = dref?.parent

        let _: String = colRef.path
        let _ = colRef.document()
        let _ = colRef.collectionID
        let _ = colRef.parent
        let _ = colRef.path
        try await colRef.addDocument(data: ["x": 0.0])

        let aq: AggregateQuery = colRef.count
        let _ = aq.query

        let aqs: AggregateQuerySnapshot = try await aq.getAggregation(source: AggregateSource.server)
        let _ = aqs.count
        let _: AggregateQuery = aqs.query

        let af: AggregateField = AggregateField.average("ABC")
        let _ = aqs.get(af)


        let _: Query = colRef.limit(to: 10)

        let _: Query = colRef.order(by: "x")
        let _: Query = colRef.order(by: "x", descending: true)

        let _: Query = colRef.whereFilter(Filter())
        let _: Query = colRef.whereFilter(Filter.orFilter([
            Filter.whereField("foo", isEqualTo: "bar"),
            Filter.whereField("foo", isNotEqualTo: "bar")
        ]))

        let _: Query = colRef.whereField("x", in: ["x"])
        //let _: Query = colRef.whereField("x", notIn: ["x"])
        let _: Query = colRef.whereField("x", isEqualTo: "x")
        let _: Query = colRef.whereField("x", arrayContains: "x")
        let _: Query = colRef.whereField("x", arrayContainsAny: ["x"])
        let _: Query = colRef.whereField("x", isGreaterThan: "x")
        let _: Query = colRef.whereField("x", isGreaterThanOrEqualTo: "x")
        let _: Query = colRef.whereField("x", isNotEqualTo: "x")
        let _: Query = colRef.whereField("x", isLessThanOrEqualTo: "x")
        let _: Query = colRef.whereField("x", isLessThan: "x")

        let fp: FieldPath = FieldPath(["x", "y"])
        let _: Query = colRef.whereField(fp, in: ["x"])
        //let _: Query = colRef.whereField(fp, notIn: ["x"])
        let _: Query = colRef.whereField(fp, isEqualTo: "x")
        let _: Query = colRef.whereField(fp, arrayContains: "x")
        let _: Query = colRef.whereField(fp, arrayContainsAny: ["x"])
        let _: Query = colRef.whereField(fp, isGreaterThan: "x")
        let _: Query = colRef.whereField(fp, isGreaterThanOrEqualTo: "x")
        let _: Query = colRef.whereField(fp, isNotEqualTo: "x")
        let _: Query = colRef.whereField(fp, isLessThanOrEqualTo: "x")
        let _: Query = colRef.whereField(fp, isLessThan: "x")


        let listenerRef: ListenerRegistration = colRef.addSnapshotListener { snap, error in
            if let snap = snap {
                let _: [DocumentChange] = snap.documentChanges
                let _: [DocumentChange] = snap.documentChanges(includeMetadataChanges: true)
                let _: [QueryDocumentSnapshot] = snap.documents
                let _: Query = snap.query
                let _: Int = snap.count
                let _: Bool = snap.isEmpty
                let _: SnapshotMetadata = snap.metadata
            }
        }
        listenerRef.remove()

        let docRef: DocumentReference = colRef.document("")
        let _: Firestore = docRef.firestore
        let _: String = docRef.documentID
        let _: String = docRef.path
        let _: CollectionReference = docRef.parent

        try await db.disableNetwork()
        try await db.enableNetwork()

        try await db.clearPersistence()
        try await db.terminate()

        //try await db.terminate()
        //_ = try await db.runTransaction { transaction, errorPtr in
        //    transaction.setData([:], forDocument: bos)
        //}

        // test encodable API variants
        //try citiesRef.addDocument(from: ["dict": "value"])
        //try citiesRef.addDocument(from: ["array", "value"])

        // Firestore Pipelines API parity. This block is intentionally not invoked; it keeps the
        // public Pipeline surface compiling against FirebaseFirestore on Darwin and SkipFirebaseFirestore on Android.
        let _: Firestore = Firestore.firestore(database: "(default)")
        let pipelineSource: PipelineSource = db.pipeline()
        let collectionPipeline: Pipeline = pipelineSource.collection("cities")
        let _: Pipeline = pipelineSource.collection(colRef, forceIndex: "idx_cities")
        let _: Pipeline = pipelineSource.collectionGroup("landmarks", forceIndex: "idx_landmarks")
        let _: Pipeline = pipelineSource.database()
        let _: Pipeline = pipelineSource.documents([docRef])
        let _: Pipeline = pipelineSource.documents(["cities/BOS"])
        let _: Pipeline = pipelineSource.create(from: colRef.whereField("name", isEqualTo: "Boston"))

        let vector = VectorValue([1.0, 2.0, 3.0])
        let _: VectorValue = FieldValue.vector([1.0, 2.0, 3.0])
        let nameField = Field("name")
        let scoreField = Field(FieldPath(["stats", "score"]))
        let populationField = Field("population")
        let condition: BooleanExpression = populationField.greaterThan(100)
        let _: BooleanExpression = DocumentMatches("coffee")
        let _: FirestorePipelineExpression = Constant.nil
        let _: FirestorePipelineExpression = Constant(vector)
        let _: FirestorePipelineExpression = Variable("cityName")
        let _: FirestorePipelineExpression = CurrentDocument()
        let _: FirestorePipelineExpression = Score()
        let rawFunction = FunctionExpression(functionName: "add", args: [populationField, Constant(1)])
        let _: FunctionExpression = FunctionExpression(functionName: "custom_function", args: [populationField], options: ["mode": "safe"])
        let _: ArrayExpression = ArrayExpression([1, "two", populationField])
        let _: MapExpression = MapExpression(["city": nameField, "population": populationField])
        let _: ConditionalExpression = ConditionalExpression(condition, then: Constant("large"), else: Constant("small"))
        let _: CurrentTimestamp = CurrentTimestamp()
        let _: ErrorExpression = ErrorExpression("pipeline error")
        let _: RandomExpression = RandomExpression()
        let _: RandomExpression = rand()
        let _: AliasedExpression = rawFunction.as("populationPlusOne")
        let _: AggregateFunction = AggregateFunction(functionName: "sum", args: [populationField])
        let countAll: AliasedAggregate = CountAll().as("count")
        let _: Ordering = nameField.ascending()
        let _: Ordering = scoreField.descending()
        let _: DistanceMeasure = .cosine
        let _: DistanceMeasure = .euclidean
        let _: DistanceMeasure = .dotProduct
        let _: TimeUnit = .day
        let _: TimePart = .dayOfWeek
        let _: TimeGranularity = .month
        let _: FunctionExpression = populationField.round()
        let _: FunctionExpression = populationField.sqrt()
        let _: FunctionExpression = populationField.pow(2)
        let _: FunctionExpression = populationField.ln()
        let _: FunctionExpression = populationField.exp()
        let _: FunctionExpression = populationField.trunc()
        let _: FunctionExpression = populationField.truncToPrecision(2)
        let _: FunctionExpression = populationField.add(1).subtract(1).multiply(2).divide(2).mod(2)
        let _: FunctionExpression = Field("regions").arrayReverse()
        let _: FunctionExpression = Field("regions").arrayConcat([ArrayExpression(["north"])])
        let _: FunctionExpression = Field("regions").arrayConcat([["north", "south"]])
        let _: BooleanExpression = Field("regions").arrayContains("north")
        let containsAllExpressions: [FirestorePipelineExpression] = [Constant("north")]
        let _: BooleanExpression = Field("regions").arrayContainsAll(containsAllExpressions)
        let _: BooleanExpression = Field("regions").arrayContainsAny(["north", "south"])
        let _: FunctionExpression = Field("regions").arrayLength()
        let _: FunctionExpression = Field("regions").arrayFilter(alias: "region", filter: Variable("region").exists())
        let _: FunctionExpression = Field("regions").arrayTransform(elementAlias: "region", transform: Variable("region"))
        let _: FunctionExpression = Field("regions").arrayTransformWithIndex(elementAlias: "region", indexAlias: "index", transform: Variable("region"))
        let _: FunctionExpression = Field("regions").arraySlice(offset: 1, length: 2)
        let _: FunctionExpression = Field("regions").arrayFirst()
        let _: FunctionExpression = Field("regions").arrayFirstN(2)
        let _: FunctionExpression = Field("regions").arrayLast()
        let _: FunctionExpression = Field("regions").arrayLastN(2)
        let _: FunctionExpression = Field("regions").arrayGet(0)
        let _: FunctionExpression = Field("regions").arrayIndexOf("north")
        let _: FunctionExpression = Field("regions").arrayLastIndexOf("north")
        let _: FunctionExpression = Field("regions").arrayIndexOfAll("north")
        let _: FunctionExpression = Field("scores").arrayMaximum()
        let _: FunctionExpression = Field("scores").arrayMinimum()
        let _: FunctionExpression = Field("scores").arrayMaximumN(2)
        let _: FunctionExpression = Field("scores").arrayMinimumN(2)
        let _: BooleanExpression = nameField.equalAny(["Boston", "Cambridge"])
        let notEqualExpressions: [FirestorePipelineExpression] = [Constant("Chicago")]
        let _: BooleanExpression = nameField.notEqualAny(notEqualExpressions)
        let _: BooleanExpression = nameField.isError()
        let _: BooleanExpression = nameField.isAbsent()
        let _: FunctionExpression = Field("regions").join(delimiter: ",")
        let _: FunctionExpression = nameField.split(delimiter: " ")
        let _: FunctionExpression = nameField.length()
        let _: FunctionExpression = nameField.charLength()
        let _: BooleanExpression = nameField.like("B%")
        let _: BooleanExpression = nameField.regexContains("Bos")
        let _: FunctionExpression = nameField.regexFind("Bos")
        let _: FunctionExpression = nameField.regexFindAll("o")
        let _: BooleanExpression = nameField.regexMatch(".*")
        let _: BooleanExpression = nameField.stringContains("Bos")
        let _: BooleanExpression = nameField.startsWith("Bo")
        let _: BooleanExpression = nameField.endsWith("on")
        let _: FunctionExpression = nameField.trim().ltrim().rtrim()
        let _: FunctionExpression = nameField.stringRepeat(2)
        let _: FunctionExpression = nameField.stringReplaceAll("B", with: "C")
        let _: FunctionExpression = nameField.stringReplaceOne("B", with: "C")
        let _: FunctionExpression = nameField.stringIndexOf("o")
        let _: FunctionExpression = nameField.stringConcat([" ", Field("state")])
        let _: FunctionExpression = nameField.reverse()
        let _: FunctionExpression = nameField.stringReverse()
        let _: FunctionExpression = nameField.byteLength()
        let _: FunctionExpression = nameField.substring(position: 0, length: 2)
        let _: FunctionExpression = CurrentDocument().getField("profile").mapGet("displayName")
        let _: FunctionExpression = CurrentDocument().mapRemove("private")
        let _: FunctionExpression = CurrentDocument().mapMerge([MapExpression(["active": true])])
        #if SKIP
        let _: FunctionExpression = CurrentDocument().mapSet("active", true, ["level", 1])
        let _: FirestorePipelineExpression = switchOn(condition, Constant("large"), [Constant("small")])
        #else
        let _: FunctionExpression = CurrentDocument().mapSet("active", true, "level", 1)
        let _: FirestorePipelineExpression = switchOn(condition, Constant("large"), Constant("small"))
        #endif
        let _: FunctionExpression = CurrentDocument().mapKeys()
        let _: FunctionExpression = CurrentDocument().mapValues()
        let _: FunctionExpression = CurrentDocument().mapEntries()
        let _: FunctionExpression = Field("embedding").vectorLength()
        let _: FunctionExpression = Field("embedding").cosineDistance([1.0, 2.0, 3.0])
        let _: FunctionExpression = Field("embedding").dotProduct(vector)
        let _: FunctionExpression = Field("embedding").euclideanDistance(Constant(vector))
        let _: AggregateFunction = populationField.first()
        let _: AggregateFunction = populationField.last()
        let _: AggregateFunction = nameField.arrayAgg()
        let _: AggregateFunction = nameField.arrayAggDistinct()
        let _: FunctionExpression = populationField.logicalMaximum([100, Field("baseline")])
        let minimumExpressions: [FirestorePipelineExpression] = [Field("floor")]
        let _: FunctionExpression = populationField.logicalMinimum(minimumExpressions)
        let _: FunctionExpression = populationField.unixMillisToTimestamp()
        let _: FunctionExpression = CurrentTimestamp().timestampToUnixMillis()
        let _: FunctionExpression = CurrentTimestamp().timestampTruncate(granularity: .day)
        let _: FunctionExpression = CurrentTimestamp().timestampDiff(CurrentTimestamp(), .day)
        let _: FunctionExpression = CurrentTimestamp().timestampExtract(part: .day)
        let _: FunctionExpression = CurrentTimestamp().timestampAdd(1, .day)
        let _: FunctionExpression = CurrentTimestamp().timestampSubtract(1, .day)
        let _: FunctionExpression = CurrentDocument().documentId()
        let _: FunctionExpression = CurrentDocument().collectionId()
        let _: FunctionExpression = CurrentDocument().parent()
        let _: FunctionExpression = nameField.ifError(Constant("fallback"))
        let _: FunctionExpression = nameField.ifAbsent("fallback")
        let _: FunctionExpression = nameField.ifNull("fallback")
        let _: FunctionExpression = nameField.coalesce([Field("fallbackName")])
        let _: FunctionExpression = nameField.concat(["-", Field("state")])
        let _: FunctionExpression = nameField.type()
        let _: BooleanExpression = nameField.isType("string")

        let _: Pipeline = collectionPipeline.addFields([rawFunction.as("populationPlusOne")])
        let _: Pipeline = collectionPipeline.removeFields([Field("private")])
        let _: Pipeline = collectionPipeline.removeFields(["private"])
        let _: Pipeline = collectionPipeline.select([nameField, rawFunction.as("populationPlusOne")])
        let _: Pipeline = collectionPipeline.select(["name", "population"])
        let _: Pipeline = collectionPipeline.where(condition)
        let _: Pipeline = collectionPipeline.offset(1).limit(2)
        let _: Pipeline = collectionPipeline.define([nameField.as("cityName")])
        let _: Pipeline = collectionPipeline.distinct(["country"])
        let _: Pipeline = collectionPipeline.distinct([Field("country")])
        let _: Pipeline = collectionPipeline.aggregate([countAll])
        let _: Pipeline = collectionPipeline.aggregate([populationField.sum().as("populationSum")], groups: [Field("country")])
        let _: Pipeline = collectionPipeline.findNearest(field: Field("embedding"), vectorValue: vector, distanceMeasure: .cosine, limit: 5, distanceField: "distance")
        let _: Pipeline = collectionPipeline.sort([populationField.descending()])
        let _: Pipeline = collectionPipeline.replace(with: CurrentDocument())
        let _: Pipeline = collectionPipeline.replace(with: "profile")
        let _: Pipeline = collectionPipeline.sample(count: 5)
        let _: Pipeline = collectionPipeline.sample(percentage: 0.25)
        let _: Pipeline = collectionPipeline.search(query: DocumentMatches("coffee"), languageCode: "en", retrievalDepth: 10, sort: [Score().descending()], offset: 1, limit: 3, addFields: [Score().as("searchScore")])
        let _: Pipeline = collectionPipeline.search(query: "coffee", languageCode: "en", retrievalDepth: 10, sort: [Score().descending()], offset: 1, limit: 3, addFields: [Score().as("searchScore")])
        let _: Pipeline = collectionPipeline.union(with: pipelineSource.collection("towns"))
        let _: Pipeline = collectionPipeline.unnest(Field("regions").as("region"), indexField: "regionIndex")
        let _: Pipeline = collectionPipeline.rawStage(name: "limit", params: [1], options: ["debug": false])
        let _: FirestorePipelineExpression = collectionPipeline.select([nameField]).toArrayExpression()
        let _: FirestorePipelineExpression = collectionPipeline.aggregate([countAll]).toScalarExpression()

        let subcollection = Subcollection("reviews")
        let _: Pipeline = subcollection.aggregate([Field("rating").average().as("avgRating")])
        let _: FirestorePipelineExpression = subcollection.select([Field("rating")]).toArrayExpression()

        let pipelineSnapshot: Pipeline.Snapshot = try await collectionPipeline.limit(1).execute()
        let _: Timestamp = pipelineSnapshot.executionTime
        let _: [PipelineResult] = pipelineSnapshot.results
        if let result = pipelineSnapshot.results.first {
            let _: DocumentReference? = result.ref
            let _: String? = result.id
            let _: Timestamp? = result.createTime
            let _: Timestamp? = result.updateTime
            let _ = result.data
            let _ = result.get("name")
            let _ = result.get(FieldPath(["stats", "score"]))
            let _ = result.get(nameField)
        }
    }

    func testFirestore() async throws {
        XCTAssertEqual(appName, self.app.name)

        let citiesRef = db.collection("cities")

        do {
            let snapshot = try await citiesRef.getDocuments()
            for document in snapshot.documents {
                logger.log("read citiesRef: \(document.documentID) => \(document.data())")
            }
        }

        let ts = Timestamp(seconds: 12345, nanoseconds: 100_000_000)
        XCTAssertEqual(12345, ts.seconds)
        XCTAssertEqual(100_000_000, ts.nanoseconds)
        XCTAssertEqual(12345.1, ts.dateValue().timeIntervalSince1970, accuracy: 0.001)

        let bos: DocumentReference = citiesRef.document("BOS")

        var listenerChanges = 0
        let docListener: ListenerRegistration = bos.addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            listenerChanges += 1
        }
        defer { docListener.remove() }

        XCTAssertEqual(0, listenerChanges)
        try await bos.setData(Self.bostonData)
        if !isJava { // doesn't fire immediately on Android
            XCTAssertEqual(3, listenerChanges)
        }

        let bdoc: DocumentSnapshot = try await bos.getDocument()
        XCTAssertEqual("Boston", bdoc.get("name") as? String)

        XCTAssertNotNil(bdoc.get("regions"))

        // SKIP NOWARN
        XCTAssertEqual(["east_coast", "new_england"], bdoc.get("regions") as? [String])

        XCTAssertNotNil(bdoc.get("time"))
        XCTAssertEqual(Timestamp(date: Date(timeIntervalSince1970: 1234)), bdoc.get("time") as? Timestamp)

        XCTAssertEqual(555000, bdoc.get("population") as? Int64)
        let bosData: [String: Any] = ["population": 675000, "regions": FieldValue.arrayUnion(["new_england", "north_east"]), "newarray": FieldValue.arrayUnion([["foo": "bar"]])]
        try await bos.updateData(bosData)

        XCTAssertEqual(555000, bdoc.get("population") as? Int64)
        let bdoc2 = try await bos.getDocument()
        XCTAssertEqual(675000, bdoc2.get("population") as? Int64)
        // SKIP NOWARN
        XCTAssertEqual(3, (bdoc2.get("regions") as? [String] ?? []).count)
        // SKIP NOWARN
        XCTAssertEqual("bar", (bdoc2.get("newarray") as? [[String: String]] ?? []).first?["foo"])

        try await citiesRef.document("LA").setData([
            "name": "Los Angeles",
            "state": "CA",
            "country": "USA",
            "capital": false,
            "population": 3900000,
            "regions": ["west_coast", "socal"]
        ])
        try await citiesRef.document("DC").setData([
            "name": "Washington D.C.",
            "country": "USA",
            "capital": true,
            "population": 680000,
            "regions": ["east_coast"]
        ])
        try await citiesRef.document("TOK").setData([
            "name": "Tokyo",
            "country": "Japan",
            "capital": true,
            "population": 9000000,
            "regions": ["kanto", "honshu"]
        ])
        try await citiesRef.document("BJ").setData([
            "name": "Beijing",
            "country": "China",
            "capital": true,
            "population": 21500000,
            "regions": ["jingjinji", "hebei"]
        ])

        do {
            let snapshot: QuerySnapshot = try await citiesRef.getDocuments()
            for document in snapshot.documents {
                logger.log("read citiesRef: \(document.documentID) => \(document.data())")
            }
        }

        XCTAssertEqual(appName, self.app.name)

        let tblref = db.collection("testFirestoreQuery")
        let doc = try await tblref.addDocument(data: [
            "when": Date.now.timeIntervalSince1970
        ])
        logger.log("testFirestoreQuery: id=\(doc.documentID)")

        var changes = 0
        let reg = tblref.addSnapshotListener(includeMetadataChanges: true, listener: { querySnapshot, error in
            changes += 1
            guard let querySnapshot else {
                return XCTFail("no query snapshot")
            }
            logger.log("querySnapshot: \(querySnapshot)")
            for diff in querySnapshot.documentChanges {
                logger.log("  diff: \(diff)")
            }
        })
        defer { reg.remove() }

        let when = Date.now.timeIntervalSince1970
        XCTAssertEqual(0, changes)

        let doc2Ref = try await tblref.addDocument(data: [
            "when": when
        ])
        if !isJava { // doesn't fire immediately on Android
            XCTAssertEqual(2, changes)
        }

        let doc2 = try await doc2Ref.getDocument()
        XCTAssertEqual(when, doc2.get("when") as? Double)

        try await assertExistsFalseForNonExistentDocument()

        try await assertExistsTrueForExistentDocument()
    }

    // test disabled because we cannot seem to have multiple simultaneous firebase setups running
    func DISABLEDtestFirestoreBundles() async throws {

        // see Resources/ firestore_bundle-1.json, firestore_bundle-2.json, firestore_bundle-3.json
        let bundle1 = try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "firestore_bundle-1", withExtension: "json")))

        let data = bundle1

        // the name of the app must match the bundle to be loaded, or else:
        // 10.19.1 - [FirebaseFirestore][I-FST000001] Failed to GetNextElement() from bundle with error Resource name is not valid for current instance: projects/react-native-firebase-testing/databases/(default)/documents

        let appName = "react-native-firebase-testing"

        let options = FirebaseOptions(googleAppID: self.app.options.googleAppID, gcmSenderID: self.app.options.gcmSenderID)
        options.projectID = appName
        options.storageBucket = appName + ".appspot.com"

        options.apiKey = self.app.options.apiKey
        if options.apiKey == nil {
            fatalError("no api key set in SKIP_FIREBASE_API_KEY environment")
        }

        FirebaseApp.configure(name: appName, options: options)

        // the app is registered statically, so check to see if it has been registered
        // nonisolated(unsafe): the @MainActor class isolates this local, but it is sent into
        // the nonisolated `delete()` below; safe because access is already serialized.
        nonisolated(unsafe) let cacheApp = try XCTUnwrap(FirebaseApp.app(name: appName))

        let store = Firestore.firestore(app: cacheApp)

        let progress: LoadBundleTaskProgress = try await store.loadBundle(data)
        XCTAssertEqual(12, progress.totalDocuments)

        let cacheQuery = await store.getQuery(named: "named-bundle-test-1")
        // SKIP NOWARN
        let docs = try await XCTUnwrap(cacheQuery).getDocuments(source: FirestoreSource.cache)
        XCTAssertEqual(12, docs.count)

        // SKIP NOWARN
        await cacheApp.delete()
    }

    func assertExistsFalseForNonExistentDocument() async throws {
        XCTAssertEqual(appName, self.app.name)
        let citiesRef = db.collection("cities")
        let bos = citiesRef.document("BOS")
        try await bos.setData(Self.bostonData)
        let ref = citiesRef.document("NON_EXISTENT_DOCUMENT")
        do {
            let snapshot = try await ref.getDocument()
            XCTAssertFalse(snapshot.exists)
            XCTAssertNil(snapshot.data())
        }
        do {
            try await ref.updateData(Self.bostonData)
            XCTFail("updateData should throw on non-existent document")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, FirestoreErrorDomain)
            XCTAssertEqual(nsError.code, FirestoreErrorCode.notFound.rawValue)
        }
    }

    func assertExistsTrueForExistentDocument() async throws {
        XCTAssertEqual(appName, self.app.name)
        let citiesRef = db.collection("cities")
        let bos = citiesRef.document("BOS")
        try await bos.setData(Self.bostonData)
        let ref = citiesRef.document("BOS")
        do {
            let snapshot = try await ref.getDocument()
            XCTAssertTrue(snapshot.exists)
        }
    }

    private func requireFirestorePipelinesLive() throws {
        if ProcessInfo.processInfo.environment["SKIP_FIRESTORE_PIPELINES_LIVE"] != "1" {
            throw XCTSkip("Set SKIP_FIRESTORE_PIPELINES_LIVE=1 to run Firestore Enterprise Pipeline execution tests.")
        }
    }

    private func requireFirestorePipelinesVectorLive() throws {
        if ProcessInfo.processInfo.environment["SKIP_FIRESTORE_PIPELINES_VECTOR_LIVE"] != "1" {
            throw XCTSkip("Set SKIP_FIRESTORE_PIPELINES_VECTOR_LIVE=1 to run vector-indexed Pipeline tests.")
        }
    }

    private func makePipelineLiveCollection(_ label: String) -> CollectionReference {
        let timestamp = Int(Date.now.timeIntervalSince1970 * 1000)
        return db.collection("pipeline_live_\(label)_\(timestamp)")
    }

    private func seedPipelineLiveCities(_ label: String) async throws -> CollectionReference {
        let collection = makePipelineLiveCollection(label)
        try await collection.document("BOS").setData([
            "name": "Boston",
            "country": "USA",
            "capital": false,
            "population": Int64(675000),
            "regions": ["east_coast", "new_england"],
            "private": "remove-me",
            "embedding": FieldValue.vector([0.1, 0.2, 0.3])
        ])
        try await collection.document("SF").setData([
            "name": "San Francisco",
            "country": "USA",
            "capital": false,
            "population": Int64(860001),
            "regions": ["west_coast", "norcal"],
            "private": "remove-me",
            "embedding": FieldValue.vector([0.2, 0.3, 0.4])
        ])
        try await collection.document("TOK").setData([
            "name": "Tokyo",
            "country": "Japan",
            "capital": true,
            "population": Int64(9000000),
            "regions": ["kanto", "honshu"],
            "private": "remove-me",
            "embedding": FieldValue.vector([0.9, 0.1, 0.2])
        ])
        return collection
    }

    func testFirestorePipelineLiveCollectionStages() async throws {
        try requireFirestorePipelinesLive()
        let collection = try await seedPipelineLiveCities("stages")

        let snapshot = try await db.pipeline()
            .collection(collection)
            .where(Field("population").greaterThan(Int64(600000)))
            .addFields([Field("population").add(1).as("populationPlusOne")])
            .removeFields(["private"])
            .select([Field("name"), Field("country"), Field("populationPlusOne")])
            .sort([Field("populationPlusOne").descending()])
            .offset(0)
            .limit(2)
            .execute()

        XCTAssertEqual(2, snapshot.results.count)
        XCTAssertNotNil(snapshot.executionTime)
        XCTAssertEqual("Tokyo", snapshot.results.first?.get("name") as? String)
        XCTAssertNil(snapshot.results.first?.get("private"))
        XCTAssertNotNil(snapshot.results.first?.get("populationPlusOne"))
    }

    func testFirestorePipelineLiveAggregateDistinctUnionUnnestAndSubqueries() async throws {
        try requireFirestorePipelinesLive()
        let first = try await seedPipelineLiveCities("shapeA")
        let second = try await seedPipelineLiveCities("shapeB")
        let source = db.pipeline()

        let aggregate = try await source.collection(first)
            .aggregate([CountAll().as("count"), Field("population").sum().as("populationSum")], groups: [Field("country")])
            .execute()
        XCTAssertGreaterThanOrEqual(aggregate.results.count, 2)
        XCTAssertTrue(aggregate.results.contains { $0.get("country") as? String == "USA" })

        let distinct = try await source.collection(first)
            .distinct([Field("country")])
            .execute()
        XCTAssertGreaterThanOrEqual(distinct.results.count, 2)

        let union = try await source.collection(first)
            .select(["name"])
            .union(with: source.collection(second).select(["name"]))
            .execute()
        XCTAssertGreaterThanOrEqual(union.results.count, 6)

        let unnest = try await source.collection(first)
            .unnest(Field("regions").as("region"), indexField: "regionIndex")
            .select(["name", "region", "regionIndex"])
            .limit(4)
            .execute()
        XCTAssertFalse(unnest.results.isEmpty)
        XCTAssertNotNil(unnest.results.first?.get("region"))
        XCTAssertNotNil(unnest.results.first?.get("regionIndex"))

        let withSubqueries = try await source.collection(first)
            .limit(1)
            .addFields([
                source.collection(first).aggregate([CountAll().as("count")]).toScalarExpression().as("totalCount"),
                source.collection(first).select([Field("name")]).toArrayExpression().as("allCities")
            ])
            .execute()
        XCTAssertEqual(1, withSubqueries.results.count)
        XCTAssertNotNil(withSubqueries.results.first?.get("totalCount"))
        XCTAssertNotNil(withSubqueries.results.first?.get("allCities"))
    }

    func testFirestorePipelineLiveVectorFindNearest() async throws {
        try requireFirestorePipelinesLive()
        try requireFirestorePipelinesVectorLive()
        let collection = try await seedPipelineLiveCities("vector")

        let snapshot = try await db.pipeline()
            .collection(collection)
            .findNearest(field: Field("embedding"), vectorValue: VectorValue([0.1, 0.2, 0.31]), distanceMeasure: .euclidean, limit: 2, distanceField: "distance")
            .execute()

        XCTAssertEqual(2, snapshot.results.count)
        XCTAssertNotNil(snapshot.results.first?.get("distance"))
        XCTAssertNotNil(snapshot.results.first?.get("embedding") as? VectorValue)
    }

    func testFirestorePipelineLiveValidationFailures() async throws {
        try requireFirestorePipelinesLive()
        let collection = try await seedPipelineLiveCities("failures")

        do {
            _ = try await db.pipeline()
                .collection(collection)
                .select([Field("name").as("duplicate"), Field("country").as("duplicate")])
                .execute()
            XCTFail("Duplicate Pipeline aliases should fail before execution.")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(FirestoreErrorDomain, nsError.domain)
            XCTAssertEqual(FirestoreErrorCode.invalidArgument.rawValue, nsError.code)
        }

        do {
            _ = try await Subcollection("reviews").limit(1).execute()
            XCTFail("Subcollection pipelines cannot execute directly.")
        } catch {
            XCTAssertEqual(FirestoreErrorDomain, (error as NSError).domain)
        }

        do {
            let otherDb = Firestore.firestore(database: "other")
            _ = try await db.pipeline().documents([otherDb.document("cities/BOS")]).execute()
            XCTFail("Document references from another Firestore instance should fail.")
        } catch {
            XCTAssertEqual(FirestoreErrorDomain, (error as NSError).domain)
        }
    }
}

extension SkipFirebaseFirestoreTests {
    private static let bostonData: [String : Any] = [
        "name": "Boston",
        "state": "MA",
        "country": "USA",
        "capital": false,
        "population": 555000,
        "regions": ["east_coast", "new_england"],
        "time": Timestamp(date: Date(timeIntervalSince1970: 1234))
    ]
}

struct TestData : Codable, Hashable {
    var testModuleName: String
}

// MARK: - Encoder/decoder unit tests (Android/Skip only — FirestoreEncoder/Decoder are Skip-only types)

// Inline structs must be file-level in Skip (no type declarations inside functions)
#if SKIP
struct CodableCity: Codable, Equatable {
    @DocumentID var id: String?
    var name: String
    var population: Int64
    var active: Bool
    var score: Double
    var createdAt: Date?
    var updatedAt: Timestamp?
    @ServerTimestamp var serverTime: Timestamp?
}

struct _MString: Codable { var name: String }
struct _MBool: Codable { var active: Bool }
struct _MDate: Codable { var createdAt: Date }
struct _MTimestamp: Codable { var ts: Timestamp }
struct _MServerTimestamp: Codable { @ServerTimestamp var ts: Timestamp? }
struct _MDocumentID: Codable { @DocumentID var id: String?; var name: String }
struct _MVector: Codable { var embedding: VectorValue }

@MainActor final class FirestoreCodecTests: XCTestCase {

    func testEncoderPreservesString() throws {
        let out = try FirestoreEncoder().encode(_MString(name: "Boston"))
        XCTAssertEqual(out["name"] as? String, "Boston")
    }

    func testEncoderPreservesBoolTrue() throws {
        let out = try FirestoreEncoder().encode(_MBool(active: true))
        XCTAssertEqual(out["active"] as? Bool, true)
    }

    func testEncoderPreservesBoolFalse() throws {
        let out = try FirestoreEncoder().encode(_MBool(active: false))
        XCTAssertEqual(out["active"] as? Bool, false)
    }

    func testEncoderConvertsDateToTimestamp() throws {
        let date = Date(timeIntervalSince1970: 1_234_567_890)
        let out = try FirestoreEncoder().encode(_MDate(createdAt: date))
        let ts = try XCTUnwrap(out["createdAt"] as? Timestamp)
        XCTAssertEqual(ts.seconds, 1_234_567_890)
        XCTAssertEqual(ts.nanoseconds, 0)
    }

    func testEncoderPreservesTimestampField() throws {
        let ts = Timestamp(seconds: 999, nanoseconds: 42)
        let out = try FirestoreEncoder().encode(_MTimestamp(ts: ts))
        let result = try XCTUnwrap(out["ts"] as? Timestamp)
        XCTAssertEqual(result.seconds, 999)
        XCTAssertEqual(result.nanoseconds, 42)
    }

    func testFieldValueVectorCreatesVectorValue() {
        let vector = FieldValue.vector([0.0, 1.5, 3.25])
        XCTAssertEqual(vector, VectorValue([0.0, 1.5, 3.25]))
    }

    func testEncoderPreservesVectorValue() throws {
        let vector = VectorValue([0.25, 1.5, 2.75])
        let out = try FirestoreEncoder().encode(_MVector(embedding: vector))
        let result = try XCTUnwrap(out["embedding"] as? VectorValue)
        XCTAssertEqual(result, vector)
    }

    func testDecoderPreservesVectorValue() throws {
        let vector = VectorValue([9.0, 8.0, 7.0])
        let model: _MVector = try FirestoreDecoder().decode(from: ["embedding": vector])
        XCTAssertEqual(model.embedding, vector)
    }

    func testEncoderServerTimestampNilBecomesFieldValue() throws {
        let out = try FirestoreEncoder().encode(_MServerTimestamp())
        XCTAssertTrue(out["ts"] is com.google.firebase.firestore.FieldValue)
    }

    func testEncoderServerTimestampNonNilPreservesTimestamp() throws {
        let ts = Timestamp(seconds: 1000, nanoseconds: 0)
        let out = try FirestoreEncoder().encode(_MServerTimestamp(ts: ts))
        let result = try XCTUnwrap(out["ts"] as? Timestamp)
        XCTAssertEqual(result.seconds, 1000)
    }

    func testEncoderDocumentIDNotEncoded() throws {
        let out = try FirestoreEncoder().encode(_MDocumentID(name: "Test"))
        XCTAssertNil(out["id"])
        XCTAssertEqual(out["name"] as? String, "Test")
    }

    func testDecoderTimestampToDateField() throws {
        let ts = Timestamp(seconds: 1_234_567_890, nanoseconds: 0)
        let dict: [String: Any] = ["createdAt": ts]
        let m: _MDate = try FirestoreDecoder().decode(from: dict)
        XCTAssertEqual(m.createdAt.timeIntervalSince1970, 1_234_567_890, accuracy: 1.0)
    }

    func testDecoderTimestampToTimestampField() throws {
        let ts = Timestamp(seconds: 999, nanoseconds: 42)
        let dict: [String: Any] = ["ts": ts]
        let m: _MTimestamp = try FirestoreDecoder().decode(from: dict)
        XCTAssertEqual(m.ts.seconds, 999)
        XCTAssertEqual(m.ts.nanoseconds, 42)
    }

    func testDecoderDocumentIDPopulatedWhenProvided() throws {
        let dict: [String: Any] = ["name": "Boston"]
        let m: _MDocumentID = try FirestoreDecoder().decode(from: dict, documentID: "BOS")
        XCTAssertEqual(m.id, "BOS")
        XCTAssertEqual(m.name, "Boston")
    }

    func testDecoderDocumentIDNilWhenNotProvided() throws {
        let dict: [String: Any] = ["name": "Boston"]
        let m: _MDocumentID = try FirestoreDecoder().decode(from: dict)
        XCTAssertNil(m.id)
        XCTAssertEqual(m.name, "Boston")
    }

    func testDecoderDocumentIDTakesFromRef_NotFromData() throws {
        let dict: [String: Any] = ["name": "Boston", "id": "FROM_DATA"]
        let m: _MDocumentID = try FirestoreDecoder().decode(from: dict, documentID: "FROM_REF")
        XCTAssertEqual(m.id, "FROM_REF")
    }

    func testRoundtripCodableCity() throws {
        let city = CodableCity(
            name: "Boston",
            population: 675_000,
            active: true,
            score: 9.5,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            updatedAt: Timestamp(seconds: 2_000_000, nanoseconds: 0),
            serverTime: Timestamp(seconds: 3_000_000, nanoseconds: 0)
        )
        let encoded = try FirestoreEncoder().encode(city)
        let decoded: CodableCity = try FirestoreDecoder().decode(from: encoded, documentID: "BOS")
        XCTAssertEqual(decoded.id, "BOS")
        XCTAssertEqual(decoded.name, "Boston")
        XCTAssertEqual(decoded.population, 675_000)
        XCTAssertEqual(decoded.active, true)
        XCTAssertEqual(decoded.score, 9.5, accuracy: 0.001)
        XCTAssertEqual(decoded.updatedAt?.seconds, 2_000_000)
        XCTAssertEqual(decoded.serverTime?.seconds, 3_000_000)
    }
}
#endif
