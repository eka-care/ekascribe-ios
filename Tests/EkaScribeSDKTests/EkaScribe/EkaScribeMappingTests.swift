import XCTest
@testable import EkaScribeSDK

final class EkaScribeMappingTests: XCTestCase {

    // MARK: - mapSession Tests

    func testMapSessionValidRecord() {
        let record = SessionRecord(
            sessionId: "s1",
            createdAt: 1000,
            updatedAt: 2000,
            state: SessionState.recording.rawValue,
            chunkCount: 5,
            uploadStage: UploadStage.commit.rawValue
        )

        let result = EkaScribe.mapSession(record)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.sessionId, "s1")
        XCTAssertEqual(result?.createdAt, 1000)
        XCTAssertEqual(result?.updatedAt, 2000)
        XCTAssertEqual(result?.state, SessionState.recording.rawValue)
        XCTAssertEqual(result?.chunkCount, 5)
        XCTAssertEqual(result?.uploadStage, .commit)
    }

    func testMapSessionInvalidStage() {
        let record = SessionRecord(
            sessionId: "s1",
            createdAt: 1000,
            updatedAt: 2000,
            state: SessionState.idle.rawValue,
            chunkCount: 0,
            uploadStage: "INVALID_STAGE"
        )

        let result = EkaScribe.mapSession(record)
        XCTAssertNil(result)
    }

    func testMapSessionAllUploadStages() {
        let stages: [UploadStage] = [.initialize, .stop, .commit, .analyzing, .completed, .failure, .error]

        for stage in stages {
            let record = SessionRecord(
                sessionId: "s-\(stage.rawValue)",
                createdAt: 100,
                updatedAt: 200,
                state: "idle",
                chunkCount: 0,
                uploadStage: stage.rawValue
            )
            let result = EkaScribe.mapSession(record)
            XCTAssertNotNil(result, "mapSession should succeed for stage \(stage.rawValue)")
            XCTAssertEqual(result?.uploadStage, stage)
        }
    }

    func testMapSessionPreservesTimestamps() {
        let record = SessionRecord(
            sessionId: "ts-test",
            createdAt: 1718000000000,
            updatedAt: 1718000060000,
            state: "completed",
            chunkCount: 3,
            uploadStage: UploadStage.completed.rawValue
        )

        let result = EkaScribe.mapSession(record)
        XCTAssertEqual(result?.createdAt, 1718000000000)
        XCTAssertEqual(result?.updatedAt, 1718000060000)
    }

    func testMapSessionPreservesChunkCount() {
        let record = SessionRecord(
            sessionId: "cc-test",
            createdAt: 100,
            updatedAt: 200,
            state: "recording",
            chunkCount: 42,
            uploadStage: UploadStage.stop.rawValue
        )

        let result = EkaScribe.mapSession(record)
        XCTAssertEqual(result?.chunkCount, 42)
    }

    // MARK: - mapUserConfigs Tests

    func testMapUserConfigsNilData() {
        let response = GetConfigResponse(data: nil)
        let result = EkaScribe.shared.mapUserConfigs(response)
        XCTAssertNil(result)
    }

    func testMapUserConfigsEmptyData() {
        let data = GetConfigResponse.ConfigData(
            consultationModes: nil,
            supportedLanguages: nil,
            outputTemplates: nil,
            selectedUserPreferences: nil,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.consultationModes.modes.isEmpty)
        XCTAssertTrue(result!.supportedLanguages.languages.isEmpty)
        XCTAssertTrue(result!.outputTemplates.templates.isEmpty)
        XCTAssertTrue(result!.modelConfigs.modelTypes.isEmpty)
        XCTAssertEqual(result!.consultationModes.maxSelection, 1)
    }

    func testMapUserConfigsConsultationModes() {
        let modes = GetConfigResponse.SelectionConfig<GetConfigResponse.ModeItem>(
            items: [
                GetConfigResponse.ModeItem(id: "m1", name: "Dictation", desc: "Record"),
                GetConfigResponse.ModeItem(id: "m2", name: "Conversation", desc: "Talk")
            ],
            maxSelection: 2
        )
        let data = GetConfigResponse.ConfigData(
            consultationModes: modes,
            supportedLanguages: nil,
            outputTemplates: nil,
            selectedUserPreferences: nil,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertEqual(result?.consultationModes.modes.count, 2)
        XCTAssertEqual(result?.consultationModes.modes[0].id, "m1")
        XCTAssertEqual(result?.consultationModes.modes[0].name, "Dictation")
        XCTAssertEqual(result?.consultationModes.modes[0].desc, "Record")
        XCTAssertEqual(result?.consultationModes.maxSelection, 2)
    }

    func testMapUserConfigsFiltersNilIds() {
        let modes = GetConfigResponse.SelectionConfig<GetConfigResponse.ModeItem>(
            items: [
                GetConfigResponse.ModeItem(id: nil, name: "No-ID", desc: nil),
                GetConfigResponse.ModeItem(id: "valid", name: nil, desc: nil),
                GetConfigResponse.ModeItem(id: "ok", name: "Valid", desc: "desc")
            ],
            maxSelection: 1
        )
        let data = GetConfigResponse.ConfigData(
            consultationModes: modes,
            supportedLanguages: nil,
            outputTemplates: nil,
            selectedUserPreferences: nil,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertEqual(result?.consultationModes.modes.count, 1)
        XCTAssertEqual(result?.consultationModes.modes[0].id, "ok")
    }

    func testMapUserConfigsSupportedLanguages() {
        let langs = GetConfigResponse.SelectionConfig<GetConfigResponse.LanguageItem>(
            items: [
                GetConfigResponse.LanguageItem(id: "en-IN", name: "English (India)"),
                GetConfigResponse.LanguageItem(id: "hi-IN", name: "Hindi")
            ],
            maxSelection: 3
        )
        let data = GetConfigResponse.ConfigData(
            consultationModes: nil,
            supportedLanguages: langs,
            outputTemplates: nil,
            selectedUserPreferences: nil,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertEqual(result?.supportedLanguages.languages.count, 2)
        XCTAssertEqual(result?.supportedLanguages.languages[0].id, "en-IN")
        XCTAssertEqual(result?.supportedLanguages.maxSelection, 3)
    }

    func testMapUserConfigsOutputTemplates() {
        let templates = GetConfigResponse.SelectionConfig<GetConfigResponse.TemplateItemDTO>(
            items: [GetConfigResponse.TemplateItemDTO(id: "t1", name: "SOAP Notes")],
            maxSelection: 5
        )
        let data = GetConfigResponse.ConfigData(
            consultationModes: nil,
            supportedLanguages: nil,
            outputTemplates: templates,
            selectedUserPreferences: nil,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertEqual(result?.outputTemplates.templates.count, 1)
        XCTAssertEqual(result?.outputTemplates.templates[0].id, "t1")
        XCTAssertEqual(result?.outputTemplates.templates[0].name, "SOAP Notes")
        XCTAssertEqual(result?.outputTemplates.maxSelection, 5)
    }

    func testMapUserConfigsModelTypes() {
        let models = GetConfigResponse.SelectionConfig<GetConfigResponse.ModelItem>(
            items: [GetConfigResponse.ModelItem(id: "pro", name: "Pro", desc: "Best quality")],
            maxSelection: 1
        )
        let data = GetConfigResponse.ConfigData(
            consultationModes: nil,
            supportedLanguages: nil,
            outputTemplates: nil,
            selectedUserPreferences: nil,
            modelConfigs: models
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertEqual(result?.modelConfigs.modelTypes.count, 1)
        XCTAssertEqual(result?.modelConfigs.modelTypes[0].id, "pro")
        XCTAssertEqual(result?.modelConfigs.modelTypes[0].desc, "Best quality")
    }

    func testMapUserConfigsSelectedPreferences() {
        let selected = GetConfigResponse.SelectedPreferencesDTO(
            consultationMode: GetConfigResponse.ModeItem(id: "dict", name: "Dictation", desc: "Record mode"),
            languages: [GetConfigResponse.LanguageItem(id: "en-IN", name: "English")],
            outputTemplates: [GetConfigResponse.TemplateItemDTO(id: "soap", name: "SOAP")],
            modelType: GetConfigResponse.ModelItem(id: "pro", name: "Pro", desc: "Best")
        )
        let data = GetConfigResponse.ConfigData(
            consultationModes: nil,
            supportedLanguages: nil,
            outputTemplates: nil,
            selectedUserPreferences: selected,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertEqual(result?.selectedUserPreferences.consultationMode?.id, "dict")
        XCTAssertEqual(result?.selectedUserPreferences.languages.count, 1)
        XCTAssertEqual(result?.selectedUserPreferences.languages[0].id, "en-IN")
        XCTAssertEqual(result?.selectedUserPreferences.outputTemplates.count, 1)
        XCTAssertEqual(result?.selectedUserPreferences.outputTemplates[0].id, "soap")
        XCTAssertEqual(result?.selectedUserPreferences.modelType?.id, "pro")
    }

    func testMapUserConfigsMaxSelectionDefaults() {
        let data = GetConfigResponse.ConfigData(
            consultationModes: GetConfigResponse.SelectionConfig<GetConfigResponse.ModeItem>(items: [], maxSelection: nil),
            supportedLanguages: GetConfigResponse.SelectionConfig<GetConfigResponse.LanguageItem>(items: [], maxSelection: nil),
            outputTemplates: GetConfigResponse.SelectionConfig<GetConfigResponse.TemplateItemDTO>(items: [], maxSelection: nil),
            selectedUserPreferences: nil,
            modelConfigs: GetConfigResponse.SelectionConfig<GetConfigResponse.ModelItem>(items: [], maxSelection: nil)
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertEqual(result?.consultationModes.maxSelection, 1)
        XCTAssertEqual(result?.supportedLanguages.maxSelection, 1)
        XCTAssertEqual(result?.outputTemplates.maxSelection, 1)
        XCTAssertEqual(result?.modelConfigs.maxSelection, 1)
    }

    func testMapUserConfigsNilSelectedPreferences() {
        let data = GetConfigResponse.ConfigData(
            consultationModes: nil,
            supportedLanguages: nil,
            outputTemplates: nil,
            selectedUserPreferences: nil,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertNil(result?.selectedUserPreferences.consultationMode)
        XCTAssertTrue(result?.selectedUserPreferences.languages.isEmpty ?? false)
        XCTAssertTrue(result?.selectedUserPreferences.outputTemplates.isEmpty ?? false)
        XCTAssertNil(result?.selectedUserPreferences.modelType)
    }

    func testMapUserConfigsPartialData() {
        let modes = GetConfigResponse.SelectionConfig<GetConfigResponse.ModeItem>(
            items: [GetConfigResponse.ModeItem(id: "m1", name: "Mode1", desc: nil)],
            maxSelection: 1
        )
        let data = GetConfigResponse.ConfigData(
            consultationModes: modes,
            supportedLanguages: nil,
            outputTemplates: nil,
            selectedUserPreferences: nil,
            modelConfigs: nil
        )
        let response = GetConfigResponse(data: data)

        let result = EkaScribe.shared.mapUserConfigs(response)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.consultationModes.modes.count, 1)
        XCTAssertTrue(result?.supportedLanguages.languages.isEmpty ?? false)
        XCTAssertTrue(result?.outputTemplates.templates.isEmpty ?? false)
    }

    // MARK: - EkaScribe Singleton Uninitialized Tests

    override func setUp() {
        super.setUp()
        EkaScribe.shared.destroy()
    }

    override func tearDown() {
        EkaScribe.shared.destroy()
        super.tearDown()
    }

    func testDestroyResetsState() {
        EkaScribe.shared.destroy()

        XCTAssertThrowsError(try EkaScribe.shared.getSessionState()) { error in
            let scribeError = error as? ScribeError
            XCTAssertEqual(scribeError?.code, .invalidConfig)
        }
    }

    func testIsRecordingWhenNotInitialized() {
        XCTAssertFalse(EkaScribe.shared.isRecording())
    }

    func testGetFullAudioFileReturnsNilWhenNotInitialized() {
        XCTAssertNil(EkaScribe.shared.getFullAudioFile())
    }

    func testGetAudioQualityThrowsWhenNotInitialized() {
        XCTAssertThrowsError(try EkaScribe.shared.getAudioQuality()) { error in
            let scribeError = error as? ScribeError
            XCTAssertEqual(scribeError?.code, .invalidConfig)
        }
    }

    func testGetVoiceActivityThrowsWhenNotInitialized() {
        XCTAssertThrowsError(try EkaScribe.shared.getVoiceActivity()) { error in
            let scribeError = error as? ScribeError
            XCTAssertEqual(scribeError?.code, .invalidConfig)
        }
    }

    func testGetUploadProgressThrowsWhenNotInitialized() {
        XCTAssertThrowsError(try EkaScribe.shared.getUploadProgress(sessionId: "test")) { error in
            let scribeError = error as? ScribeError
            XCTAssertEqual(scribeError?.code, .invalidConfig)
        }
    }

    func testRetrySessionThrowsWhenNotInitialized() async {
        do {
            _ = try await EkaScribe.shared.retrySession("test-session")
            XCTFail("Expected retrySession to throw")
        } catch let error as ScribeError {
            XCTAssertEqual(error.code, .invalidConfig)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGetSessionsThrowsWhenNotInitialized() async {
        do {
            _ = try await EkaScribe.shared.getSessions()
            XCTFail("Expected getSessions to throw")
        } catch let error as ScribeError {
            XCTAssertEqual(error.code, .invalidConfig)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGetSessionThrowsWhenNotInitialized() async {
        do {
            _ = try await EkaScribe.shared.getSession("test")
            XCTFail("Expected getSession to throw")
        } catch let error as ScribeError {
            XCTAssertEqual(error.code, .invalidConfig)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testGetSessionOutputReturnsFailureWhenNotInitialized() async {
        let result = await EkaScribe.shared.getSessionOutput("test")
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error as ScribeError):
            XCTAssertEqual(error.code, .invalidConfig)
        case .failure:
            XCTFail("Expected ScribeError")
        }
    }

    func testGetTemplatesReturnsFailureWhenNotInitialized() async {
        let result = await EkaScribe.shared.getTemplates()
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error as ScribeError):
            XCTAssertEqual(error.code, .invalidConfig)
        case .failure:
            XCTFail("Expected ScribeError")
        }
    }

    func testGetUserConfigsReturnsFailureWhenNotInitialized() async {
        let result = await EkaScribe.shared.getUserConfigs()
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error as ScribeError):
            XCTAssertEqual(error.code, .invalidConfig)
        case .failure:
            XCTFail("Expected ScribeError")
        }
    }
}
