// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

/// MXLocationService handles live location sharing
/// Note: Cannot use a protocol because of Objective-C compatibility
@objcMembers
public class MXLocationService: NSObject {
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    
    // MARK: - Setup
    
    public init(session: MXSession) {
        self.session = session
    }
    
    // MARK: - Public
    
    /// Start live location sharing for current user
    /// - Parameters:
    ///   - roomId: The roomId where the location should be shared
    ///   - description: The location description
    ///   - timeout: The location sharing duration in milliseconds
    ///   - completion: A closure called when the operation completes. Provides the event id of the event generated on the home server on success.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func startUserLocationSharing(withRoomId roomId: String,
                                         description: String?,
                                         timeout: TimeInterval,
                                         completion: @escaping (MXResponse<String>) -> Void) -> MXHTTPOperation? {
        return self.sendBeaconInfoEvent(withRoomId: roomId, description: description, timeout: timeout, completion: completion)
    }
    
    /// Get all beacon info in a room
    /// - Parameters:
    ///   - roomId: The room id of the room
    ///   - completion: Closure called when beacon fetching as ended. Give beacon info array as a result.
    public func getAllBeaconInfo(inRoomWithId roomId: String, completion: @escaping ([MXBeaconInfo]) -> Void) {
        
        guard let room = self.session.room(withRoomId: roomId) else {
            completion([])
            return
        }
        
        room.state { roomState in
            completion(roomState?.beaconInfos ?? [])
        }
    }
    
    /// Get all beacon info of a user in a room
    /// - Parameters:
    ///   - userId: The user id
    ///   - roomId: The room id
    ///   - completion: Closure called when beacon fetching as ended. Give beacon info array as a result.
    public func getAllBeaconInfo(forUserId userId: String, inRoomWithId roomId: String, completion: @escaping ([MXBeaconInfo]) -> Void) {
        self.getAllBeaconInfo(inRoomWithId: roomId) { allBeaconInfo in
            
            let userBeaconInfoList = allBeaconInfo.filter( { return $0.userId == userId })
            completion(userBeaconInfoList)
        }
    }
    
    public func getCurrentUserAllBeaconInfo(inRoomWithId roomId: String, completion: @escaping ([MXBeaconInfo]) -> Void) {
        
        guard let myUserId = self.session.myUserId else {
            return
        }
        
        self.getAllBeaconInfo(forUserId: myUserId, inRoomWithId: roomId, completion: completion)
    }
    
    /// Check if the current user is sharin is location in a room
    /// - Parameter roomId: The room id
    /// - Returns: true if the user if sharing is location
    public func isCurrentUserSharingIsLocation(inRoomWithId roomId: String) -> Bool {
        
        guard let myUserId = self.session.myUserId else {
            return false
        }
        
        guard let roomSummary = self.session.roomSummary(withRoomId: roomId) else {
            return false
        }
        
        return roomSummary.userIdsSharingLiveBeacon.contains(myUserId)
    }
        
    /// Send a beacon for an attached beacon info in a room
    /// - Parameters:
    ///   - beaconInfoEventId: The associated beacon info event id
    ///   - latitude: Coordinate latitude
    ///   - longitude: Coordinate longitude
    ///   - description: Beacon description
    ///   - threadId: the id of the thread to send the message. nil by default.
    ///   - roomId: The room id
    ///   - localEcho: a pointer to an MXEvent object.
    ///   - completion: A closure called when the operation completes. Provides the event id of the event generated on the home server on success.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func sendBeacon(withBeaconInfoEventId beaconInfoEventId: String,
                           latitude: Double,
                           longitude: Double,
                           description: String?,
                           threadId: String?,
                           inRoomWithId roomId: String,
                           localEcho: inout MXEvent?,
                                         completion: @escaping (MXResponse<String?>) -> Void) -> MXHTTPOperation? {

        guard let room = self.session.room(withRoomId: roomId) else {
            completion(.failure(MXLocationServiceError.roomNotFound))
            return nil
        }
        
        let beacon = MXBeacon(latitude: latitude, longitude: longitude, description: description, beaconInfoEventId: beaconInfoEventId)
        
        guard let eventContent = beacon.jsonDictionary() as? [String : Any] else {
            completion(.failure(MXLocationServiceError.unknown))
            return nil
        }

        return room.sendEvent(.beacon, content: eventContent, threadId: threadId, localEcho: &localEcho, completion: completion)
    }
    
    // MARK: - Private
        
    private func sendBeaconInfoEvent(withRoomId roomId: String,
                                     description: String?,
                                     timeout: TimeInterval,
                                     completion: @escaping (MXResponse<String>) -> Void) -> MXHTTPOperation? {
        
        guard let userId = self.session.myUserId else {
            completion(.failure(MXLocationServiceError.missingUserId))
            return nil
        }
                
        let stateKey = userId
        
        let beaconInfo = MXBeaconInfo(description: description,
                                      timeout: UInt64(timeout),
                                      isLive: true)
        
        
        guard let eventContent = beaconInfo.jsonDictionary() as? [String : Any] else {
            completion(.failure(MXLocationServiceError.unknown))
            return nil
        }
        
        return self.session.matrixRestClient.sendStateEvent(toRoom: roomId, eventType: .beaconInfo, content: eventContent, stateKey: stateKey) { response in
            completion(response)
        }
    }
}

// MARK: - Objective-C
extension MXLocationService {
    
    /// Start live location sharing for current user
    /// - Parameters:
    ///   - roomId: The roomId where the location should be shared
    ///   - description: The location description
    ///   - timeout: The location sharing duration
    ///   - success: A closure called when the operation is complete. Provides the event id of the event generated on the home server on success.
    ///   - failure: A closure called  when the operation fails.
    /// - Returns: a `MXHTTPOperation` instance.
    @discardableResult
    public func startUserLocationSharing(withRoomId roomId: String,
                                         description: String,
                                         timeout: TimeInterval,
                                         success: @escaping (String) -> Void,
                                         failure: @escaping (Error) -> Void) -> MXHTTPOperation? {
        return self.sendBeaconInfoEvent(withRoomId: roomId, description: description, timeout: timeout) { (response) in
            uncurryResponse(response, success: success, failure: failure)
        }
    }
}
