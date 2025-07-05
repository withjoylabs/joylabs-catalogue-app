import XCTest

/// SearchUITests - UI tests for search functionality
/// Tests the complete search user experience and interactions
final class SearchUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        app = nil
    }
    
    // MARK: - Basic Search Tests
    
    func testSearchScreenAppears() throws {
        // Test that search screen loads properly
        let searchField = app.textFields["searchField"]
        XCTAssertTrue(searchField.exists)
        XCTAssertTrue(searchField.isHittable)
        
        // Test that filter buttons exist
        let nameFilterButton = app.buttons["nameFilter"]
        let skuFilterButton = app.buttons["skuFilter"]
        let barcodeFilterButton = app.buttons["barcodeFilter"]
        
        XCTAssertTrue(nameFilterButton.exists)
        XCTAssertTrue(skuFilterButton.exists)
        XCTAssertTrue(barcodeFilterButton.exists)
    }
    
    func testBasicTextSearch() throws {
        let searchField = app.textFields["searchField"]
        
        // Tap search field and enter text
        searchField.tap()
        searchField.typeText("iPhone")
        
        // Wait for search results
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Verify results appear
        XCTAssertTrue(searchResultsList.exists)
        XCTAssertGreaterThan(searchResultsList.cells.count, 0)
    }
    
    func testSearchWithFilters() throws {
        let searchField = app.textFields["searchField"]
        let nameFilterButton = app.buttons["nameFilter"]
        let skuFilterButton = app.buttons["skuFilter"]
        
        // Enable only name filter
        nameFilterButton.tap()
        if skuFilterButton.isSelected {
            skuFilterButton.tap()
        }
        
        // Perform search
        searchField.tap()
        searchField.typeText("Test Product")
        
        // Wait for results
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Verify results appear
        XCTAssertTrue(searchResultsList.exists)
    }
    
    func testBarcodeSearch() throws {
        let searchField = app.textFields["searchField"]
        let barcodeFilterButton = app.buttons["barcodeFilter"]
        
        // Enable only barcode filter
        barcodeFilterButton.tap()
        
        // Search for barcode
        searchField.tap()
        searchField.typeText("123456789012")
        
        // Wait for results
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Verify exact match appears
        XCTAssertTrue(searchResultsList.exists)
        
        // Check for exact match indicator
        let exactMatchBadge = app.staticTexts["exactMatch"]
        XCTAssertTrue(exactMatchBadge.exists)
    }
    
    // MARK: - Search Result Interaction Tests
    
    func testTapSearchResult() throws {
        // Perform a search first
        let searchField = app.textFields["searchField"]
        searchField.tap()
        searchField.typeText("iPhone")
        
        // Wait for results
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Tap first result
        let firstResult = searchResultsList.cells.firstMatch
        XCTAssertTrue(firstResult.exists)
        firstResult.tap()
        
        // Verify detail view appears
        let detailView = app.scrollViews["itemDetailView"]
        XCTAssertTrue(detailView.waitForExistence(timeout: 3))
    }
    
    func testSearchResultActions() throws {
        // Perform a search
        let searchField = app.textFields["searchField"]
        searchField.tap()
        searchField.typeText("Test Product")
        
        // Wait for results
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Test action buttons on first result
        let firstResult = searchResultsList.cells.firstMatch
        XCTAssertTrue(firstResult.exists)
        
        // Test label button
        let labelButton = firstResult.buttons["labelAction"]
        if labelButton.exists {
            labelButton.tap()
            
            // Verify label design view appears
            let labelDesignView = app.navigationBars["Label Designer"]
            XCTAssertTrue(labelDesignView.waitForExistence(timeout: 3))
            
            // Go back
            let backButton = app.navigationBars.buttons.firstMatch
            backButton.tap()
        }
    }
    
    // MARK: - Sort and Filter Tests
    
    func testSortOptions() throws {
        // Perform a search to get results
        let searchField = app.textFields["searchField"]
        searchField.tap()
        searchField.typeText("Product")
        
        // Wait for results
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Test sort button
        let sortButton = app.buttons["sortButton"]
        if sortButton.exists {
            sortButton.tap()
            
            // Test sort options
            let sortByName = app.buttons["sortByName"]
            let sortByPrice = app.buttons["sortByPrice"]
            let sortByRelevance = app.buttons["sortByRelevance"]
            
            XCTAssertTrue(sortByName.exists)
            XCTAssertTrue(sortByPrice.exists)
            XCTAssertTrue(sortByRelevance.exists)
            
            // Select sort by name
            sortByName.tap()
            
            // Verify sort is applied (results should be reordered)
            XCTAssertTrue(searchResultsList.exists)
        }
    }
    
    func testFilterToggle() throws {
        let nameFilterButton = app.buttons["nameFilter"]
        let skuFilterButton = app.buttons["skuFilter"]
        let barcodeFilterButton = app.buttons["barcodeFilter"]
        let categoryFilterButton = app.buttons["categoryFilter"]
        
        // Test toggling filters
        let initialNameState = nameFilterButton.isSelected
        nameFilterButton.tap()
        XCTAssertNotEqual(nameFilterButton.isSelected, initialNameState)
        
        let initialSKUState = skuFilterButton.isSelected
        skuFilterButton.tap()
        XCTAssertNotEqual(skuFilterButton.isSelected, initialSKUState)
        
        let initialBarcodeState = barcodeFilterButton.isSelected
        barcodeFilterButton.tap()
        XCTAssertNotEqual(barcodeFilterButton.isSelected, initialBarcodeState)
        
        let initialCategoryState = categoryFilterButton.isSelected
        categoryFilterButton.tap()
        XCTAssertNotEqual(categoryFilterButton.isSelected, initialCategoryState)
    }
    
    // MARK: - Search Performance Tests
    
    func testSearchResponseTime() throws {
        let searchField = app.textFields["searchField"]
        
        // Measure search response time
        let startTime = Date()
        
        searchField.tap()
        searchField.typeText("iPhone")
        
        // Wait for results to appear
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        let responseTime = Date().timeIntervalSince(startTime)
        
        // Search should respond within 3 seconds
        XCTAssertLessThan(responseTime, 3.0, "Search should respond within 3 seconds")
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptySearchResults() throws {
        let searchField = app.textFields["searchField"]
        
        // Search for something that shouldn't exist
        searchField.tap()
        searchField.typeText("XYZ_NONEXISTENT_PRODUCT_123")
        
        // Wait for empty state
        let emptyStateView = app.staticTexts["noResultsMessage"]
        XCTAssertTrue(emptyStateView.waitForExistence(timeout: 5))
        
        // Verify empty state message
        XCTAssertTrue(emptyStateView.label.contains("No results found"))
    }
    
    func testSearchFieldClearButton() throws {
        let searchField = app.textFields["searchField"]
        
        // Enter text
        searchField.tap()
        searchField.typeText("Test Search")
        
        // Find and tap clear button
        let clearButton = searchField.buttons["Clear text"]
        if clearButton.exists {
            clearButton.tap()
            
            // Verify field is cleared
            XCTAssertEqual(searchField.value as? String, "")
        }
    }
    
    func testSearchWithSpecialCharacters() throws {
        let searchField = app.textFields["searchField"]
        
        // Test search with special characters
        searchField.tap()
        searchField.typeText("Product (Special) & More!")
        
        // Should not crash and should handle gracefully
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // App should still be responsive
        XCTAssertTrue(app.exists)
    }
    
    // MARK: - Accessibility Tests
    
    func testSearchAccessibility() throws {
        // Test that search elements have proper accessibility labels
        let searchField = app.textFields["searchField"]
        XCTAssertNotNil(searchField.label)
        XCTAssertTrue(searchField.isAccessibilityElement)
        
        let nameFilterButton = app.buttons["nameFilter"]
        XCTAssertNotNil(nameFilterButton.label)
        XCTAssertTrue(nameFilterButton.isAccessibilityElement)
        
        // Test VoiceOver navigation
        if UIAccessibility.isVoiceOverRunning {
            // Test that elements can be navigated with VoiceOver
            searchField.tap()
            XCTAssertTrue(searchField.hasFocus)
        }
    }
    
    // MARK: - Integration Tests
    
    func testSearchToLabelFlow() throws {
        // Complete flow from search to label creation
        let searchField = app.textFields["searchField"]
        
        // Search for item
        searchField.tap()
        searchField.typeText("iPhone")
        
        // Wait for results
        let searchResultsList = app.collectionViews["searchResults"]
        let exists = NSPredicate(format: "exists == true")
        expectation(for: exists, evaluatedWith: searchResultsList, handler: nil)
        waitForExpectations(timeout: 5, handler: nil)
        
        // Tap label action on first result
        let firstResult = searchResultsList.cells.firstMatch
        let labelButton = firstResult.buttons["labelAction"]
        
        if labelButton.exists {
            labelButton.tap()
            
            // Verify label designer opens
            let labelDesigner = app.navigationBars["Label Designer"]
            XCTAssertTrue(labelDesigner.waitForExistence(timeout: 3))
            
            // Test template selection
            let templateList = app.collectionViews["templateList"]
            if templateList.exists {
                let firstTemplate = templateList.cells.firstMatch
                firstTemplate.tap()
                
                // Verify preview updates
                let previewArea = app.scrollViews["labelPreview"]
                XCTAssertTrue(previewArea.exists)
            }
        }
    }
}
