// 
// Copyright 2023 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import XCTest
@testable import MatrixSDK

class MXKeysQuerySchedulerUnitTests: XCTestCase {
    enum Error: Swift.Error, Equatable {
        case dummy
    }
    
    typealias UserId = String
    typealias DeviceId = String
    typealias Response = [UserId: [DeviceId]]
    
    var queryCounter: Int!
    var queryStartSpy: (() -> Void)?
    var stubbedResult: Result<Response, Error>!
    var scheduler: MXKeysQueryScheduler<Response>!
    
    override func setUp() {
        queryCounter = 0
        stubbedResult = .success(
            [
                "alice": ["A"],
                "bob": ["B"],
                "carol": ["C"],
                "david": ["D"],
            ]
        )
        
        scheduler = MXKeysQueryScheduler(queryAction: queryAction(users:))
    }
    
    private func queryAction(users: [String]) async throws -> Response {
        queryCounter += 1
        
        switch stubbedResult! {
        case .success(let response):
            let res = response.filter {
                users.contains($0.key)
            }
            
            queryStartSpy?()
            try await Task.sleep(nanoseconds: 1_000_000)
            
            return res
            
        case .failure(let error):
            queryStartSpy?()
            try await Task.sleep(nanoseconds: 1_000_000)
            throw error
        }
    }
    
    private func query(
        users: Set<String>,
        completion: @escaping (Response) -> Void,
        failure: ((Swift.Error) -> Void)? = nil
    ) {
        Task.detached {
            do {
                let result = try await self.scheduler.query(users: users)
                completion(result)
            } catch {
                failure?(error)
            }
        }
    }
    
    // MARK: - Tests
    
    func test_queryAlice() {
        let exp = expectation(description: "exp")
        
        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"]
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertQueriesCount(1)
    }
    
    func test_queryAliceAndBob() {
        let exp = expectation(description: "exp")
        
        query(users: ["alice", "bob"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
                "bob": ["B"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertQueriesCount(1)
    }

    func test_queryBobAfterAlice() {
        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 2

        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }

        query(users: ["bob"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertQueriesCount(2)
    }

    func test_executeMultipleAliceQueriesOnce() {
        queryStartSpy = {
            self.stubbedResult = .success([
                "alice": ["A1", "A2"]
            ])
        }

        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 3

        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }

        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }

        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
        
        // Three queries are made but since they query the same user,
        // second and third query will simply await the results of
        // the first query
        XCTAssertQueriesCount(1)
    }

    func test_executeEachAliceQuerySeparately() {
        queryStartSpy = {
            self.stubbedResult = .success([
                "alice": ["A1", "A2"]
            ])
        }

        var exp = expectation(description: "exp")
        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        exp = expectation(description: "exp")
        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A1", "A2"],
            ])
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)

        exp = expectation(description: "exp")
        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A1", "A2"],
            ])
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 1)
        
        // Each of the three queries is made when no other query
        // is ongoing, meaning they will all execute
        XCTAssertQueriesCount(3)
    }

    func test_executeMultipleBobQueriesOnce() {
        queryStartSpy = {
            self.stubbedResult = .success([
                "bob": ["B1", "B2"]
            ])
        }

        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 2

        query(users: ["alice", "bob"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
                "bob": ["B"],
            ])
            exp.fulfill()
        }

        query(users: ["bob"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
                "bob": ["B"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
        
        // The second query contains a different set of users,
        // but since there is no user additional to the first
        // query, we do not need to execute another query
        XCTAssertQueriesCount(1)
    }

    func test_executeSecondBobQuerySeparately() {
        queryStartSpy = {
            self.stubbedResult = .success([
                "bob": ["B1", "B2"],
                "carol": ["C"]
            ])
        }

        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 2

        query(users: ["alice", "bob"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
                "bob": ["B"],
            ])
            exp.fulfill()
        }

        query(users: ["bob", "carol"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B1", "B2"],
                "carol": ["C"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)

        // The second query contains one user shared with the first,
        // but also one new user, meaning the second query cannot be
        // satisfied by the first one, and a new query has to be made
        XCTAssertQueriesCount(2)
    }

    func test_nextQueryAggregatesPendingUsers() {
        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 4

        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }

        // Making three future / pending queries has the same outcome
        // as making a single query with all users aggregated.
        query(users: ["bob"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B"],
                "carol": ["C"],
                "david": ["D"],
            ])
            exp.fulfill()
        }

        query(users: ["carol"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B"],
                "carol": ["C"],
                "david": ["D"],
            ])
            exp.fulfill()
        }

        query(users: ["david"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B"],
                "carol": ["C"],
                "david": ["D"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertQueriesCount(2)
    }
    
    func test_pendingUsersResetAfterQuery() {
        var exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 3

        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }

        query(users: ["bob"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B"],
                "carol": ["C"],
            ])
            exp.fulfill()
        }

        query(users: ["carol"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B"],
                "carol": ["C"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)

        exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 2

        query(users: ["alice"]) { response in
            XCTAssertEqual(response, [
                "alice": ["A"],
            ])
            exp.fulfill()
        }

        // Even though we have previously aggregated some users,
        // once that query completed, all future queries will
        // start with a clean list again
        query(users: ["david"]) { response in
            XCTAssertEqual(response, [
                "david": ["D"],
            ])
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)

        XCTAssertQueriesCount(4)
    }
    
    func test_queryFail() {
        scheduler = MXKeysQueryScheduler { _ in
            try! await Task.sleep(nanoseconds: 1_000_000)
            throw Error.dummy
        }
        
        let exp = expectation(description: "exp")
        
        query(users: ["alice"], completion: { _ in
            XCTFail("Should not succeed")
        }, failure: { error in
            XCTAssertEqual(error as? Error, Error.dummy)
            exp.fulfill()
        })
        
        waitForExpectations(timeout: 1)
    }
    
    func test_queryBobAfterFail() {
        stubbedResult = .failure(Error.dummy)
        queryStartSpy = {
            self.stubbedResult = .success([
                "bob": ["B"],
            ])
        }
        
        let exp = expectation(description: "exp")
        exp.expectedFulfillmentCount = 2
        
        query(users: ["alice"], completion: { _ in
            XCTFail("Should not succeed")
        }, failure: { error in
            XCTAssertEqual(error as? Error, Error.dummy)
            exp.fulfill()
        })

        query(users: ["bob"]) { response in
            XCTAssertEqual(response, [
                "bob": ["B"]
            ])
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 1)
    }
    
    // MARK: - Helpers
    
    private func XCTAssertQueriesCount(_ count: Int, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(count, queryCounter, file: file, line: line)
    }
}
