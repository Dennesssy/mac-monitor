//
//  AtomicESClient.swift
//  AtomicESClient
//
//  Created by Brandon Dalton on 4/19/23.
//  Updated for Swift 6.2 compatibility
//
//  BSD 3-Clause License: ../eula.txt
// 
//  Discussion: 
//  AtomicESClient (a very small Endpoint Security (ES) client). AtomicESClient's goal is to provide an easy 
//  to follow example for quickly getting up and going with Apple's Endpoint Security APIs. This code should 
//  only be used as if it were written on a chalkboard -- in other words, purely for example. AtomicESClient 
//  is the very distilled version of an ES client with one event subscription. Much more complete examples
//  exist. Please see the README for a few of those references! 
//
//  Swift compile: `swiftc AtomicESClient.swift -L /Applications/Xcode.app/.../MacOSX.sdk/usr/lib/ -lEndpointSecurity -lbsm -o AtomicESClient`
//  Codesign: `codesign -s $CERT --entitlements atomic_es_ents.plist --force --timestamp --options hard,kill,library-validation AtomicESClient`
//
//  Usage: `sudo ./AtomicESClient`
// 

import Foundation
import EndpointSecurity


// MARK: - Constants

/// Code signing flags from kern/cs_blobs.h
private enum CodeSigningFlags {
    static let CS_ADHOC: UInt32 = 0x00000002  // ad hoc signed
}

/// Endpoint Security event subscriptions
/// @discussion: This ES event will give you basic *high level* process execution information.
private let esEventSubscriptions: [es_event_type_t] = [
    ES_EVENT_TYPE_NOTIFY_EXEC
]

// MARK: - Process Execution Event

/// Represents a process execution event with modern Swift practices
/// @note: This provides a *basic* model for demonstration purposes.
public struct ExampleProcessExecEvent: Identifiable, Codable, Sendable {
    public let id: UUID = UUID()
    
    public let isPlatformBinary: Bool
    public let isAdhocSigned: Bool
    public let processName: String?
    public let processPath: String?
    public let signingID: String?
    public let commandLine: String?
    public let teamID: String?
    public let pid: Int32?
    
    /// Parses command line arguments from the execution event
    /// - Parameter execEvent: The execution event to parse
    /// - Returns: A space-separated command line string
    private static func parseCommandLine(from execEvent: inout es_event_exec_t) -> String {
        let argumentCount = Int(es_exec_arg_count(&execEvent))
        let arguments = (0..<argumentCount).map { index in
            String(cString: es_exec_arg(&execEvent, UInt32(index)).data)
        }
        return arguments.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    
    /// Initializes from a raw Endpoint Security message
    /// - Parameter rawEvent: Pointer to the raw ES message
    init(fromRawEvent rawEvent: UnsafePointer<es_message_t>) {
        var processExecEvent = rawEvent.pointee.event.exec
        
        self.pid = audit_token_to_pid(rawEvent.pointee.process.pointee.audit_token)
        
        let processURL = URL(fileURLWithPath: String(cString: processExecEvent.target.pointee.executable.pointee.path.data))
        self.processName = processURL.lastPathComponent
        self.processPath = String(cString: processExecEvent.target.pointee.executable.pointee.path.data)
        self.isPlatformBinary = processExecEvent.target.pointee.is_platform_binary
        self.isAdhocSigned = (processExecEvent.target.pointee.codesigning_flags & CodeSigningFlags.CS_ADHOC) == CodeSigningFlags.CS_ADHOC
        self.commandLine = Self.parseCommandLine(from: &processExecEvent)
        
        // Basic code signing information
        self.signingID = String(cString: processExecEvent.target.pointee.signing_id.data)
        
        if processExecEvent.target.pointee.team_id.length > 0 {
            self.teamID = String(cString: processExecEvent.target.pointee.team_id.data)
        } else {
            self.teamID = nil
        }
    }
}

// MARK: - ES Event Container

/// Container for Endpoint Security events with modern Swift practices
public struct ExampleESEvent: Identifiable, Codable, Sendable {
    public let id = UUID()
    
    // Top level ES message information including the `es_process_t`
    public let eventType: String?
    public let initiatingProcessName: String?
    public let initiatingProcessPath: String?
    public let initiatingProcessSigningID: String?
    public let initiatingPID: Int32?
    public let machTime: UInt64
    
    // Event-specific data
    public let execEvent: ExampleProcessExecEvent?
    
    /// Initializes from a raw Endpoint Security message
    /// - Parameter rawEvent: Pointer to the raw ES message
    init(fromRawEvent rawEvent: UnsafePointer<es_message_t>) {
        // MARK: - Top-level `es_message_t` / `es_process_t`
        // Reference: https://developer.apple.com/documentation/endpointsecurity/message
        self.machTime = rawEvent.pointee.mach_time
        self.initiatingPID = audit_token_to_pid(rawEvent.pointee.process.pointee.parent_audit_token)
        
        let executableURL = URL(fileURLWithPath: String(cString: rawEvent.pointee.process.pointee.executable.pointee.path.data))
        self.initiatingProcessPath = String(cString: rawEvent.pointee.process.pointee.executable.pointee.path.data)
        self.initiatingProcessName = executableURL.lastPathComponent
        
        // Basic code signing information
        self.initiatingProcessSigningID = String(cString: rawEvent.pointee.process.pointee.signing_id.data)
        
        // MARK: - ES event type handling
        switch rawEvent.pointee.event_type {
        case ES_EVENT_TYPE_NOTIFY_EXEC:
            self.eventType = "ES_EVENT_TYPE_NOTIFY_EXEC"
            self.execEvent = ExampleProcessExecEvent(fromRawEvent: rawEvent)
        default:
            self.eventType = "NOT_MAPPED"
            self.execEvent = nil
        }
    }
}

// MARK: - Error Types

/// Errors that can occur when working with Endpoint Security
public enum EndpointSecurityError: Error, LocalizedError, Sendable {
    case tooManyClients
    case notEntitled
    case notPermitted
    case notPrivileged
    case internalError
    case invalidArgument
    case subscriptionFailed
    case clientCreationFailed
    case unknown(es_new_client_result_t)
    
    public var errorDescription: String? {
        switch self {
        case .tooManyClients:
            return "There are too many Endpoint Security clients"
        case .notEntitled:
            return "The endpoint security entitlement is required"
        case .notPermitted:
            return "Lacking TCC permissions"
        case .notPrivileged:
            return "Caller is not running as root"
        case .internalError:
            return "Error communicating with Endpoint Security"
        case .invalidArgument:
            return "Incorrect arguments when creating Endpoint Security client"
        case .subscriptionFailed:
            return "Failed to subscribe to events"
        case .clientCreationFailed:
            return "Failed to create Endpoint Security client"
        case .unknown(let result):
            return "Unknown error occurred: \(result.rawValue)"
        }
    }
}

// MARK: - Endpoint Security Client Manager

/// Manages the Endpoint Security client with modern Swift practices
public final class EndpointSecurityClientManager: @unchecked Sendable {
    private var esClient: OpaquePointer?
    private let eventHandler: @Sendable (String) -> Void
    
    /// Initializes the manager with an event handler
    /// - Parameter eventHandler: Closure to handle JSON events
    public init(eventHandler: @escaping @Sendable (String) -> Void) {
        self.eventHandler = eventHandler
    }
    
    deinit {
        if let client = esClient {
            es_delete_client(client)
        }
    }
    
    /// Converts an encodable event to JSON string
    /// - Parameter value: The encodable value to convert
    /// - Returns: JSON string representation
    /// - Throws: Encoding errors
    public static func eventToJSON<T: Encodable>(value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        
        let encodedData = try encoder.encode(value)
        guard let jsonString = String(data: encodedData, encoding: .utf8) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: [],
                debugDescription: "Unable to convert encoded data to UTF-8 string"
            ))
        }
        
        return jsonString
    }
    
    /// Creates and configures a new Endpoint Security client
    /// - Returns: Pointer to the ES client
    /// - Throws: EndpointSecurityError for various failure conditions
    public func createESClient() throws -> OpaquePointer {
        var client: OpaquePointer?
        
        // Create new ES client with event callback
        let result = es_new_client(&client) { [eventHandler] _, event in
            do {
                let jsonEvent = try EndpointSecurityClientManager.eventToJSON(
                    value: ExampleESEvent(fromRawEvent: event)
                )
                eventHandler(jsonEvent)
            } catch {
                print("[ES CLIENT ERROR] Failed to process event: \(error)")
            }
        }
        
        // Handle client creation result
        switch result {
        case ES_NEW_CLIENT_RESULT_ERR_TOO_MANY_CLIENTS:
            throw EndpointSecurityError.tooManyClients
        case ES_NEW_CLIENT_RESULT_ERR_NOT_ENTITLED:
            throw EndpointSecurityError.notEntitled
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PERMITTED:
            throw EndpointSecurityError.notPermitted
        case ES_NEW_CLIENT_RESULT_ERR_NOT_PRIVILEGED:
            throw EndpointSecurityError.notPrivileged
        case ES_NEW_CLIENT_RESULT_ERR_INTERNAL:
            throw EndpointSecurityError.internalError
        case ES_NEW_CLIENT_RESULT_ERR_INVALID_ARGUMENT:
            throw EndpointSecurityError.invalidArgument
        case ES_NEW_CLIENT_RESULT_SUCCESS:
            print("[ES CLIENT SUCCESS] Successfully created Endpoint Security client")
        default:
            throw EndpointSecurityError.unknown(result)
        }
        
        guard let validClient = client else {
            throw EndpointSecurityError.clientCreationFailed
        }
        
        // Subscribe to events
        let subscriptionResult = es_subscribe(
            validClient,
            esEventSubscriptions,
            UInt32(esEventSubscriptions.count)
        )
        
        if subscriptionResult != ES_RETURN_SUCCESS {
            es_delete_client(validClient)
            throw EndpointSecurityError.subscriptionFailed
        }
        
        self.esClient = validClient
        return validClient
    }
}

// MARK: - Application Entry Point

/// Event logger that prints JSON events to stdout
/// - Parameter jsonEvent: The JSON representation of the event
@Sendable func logger(jsonEvent: String) {
    print(jsonEvent)
}

/// Creates and starts an Endpoint Security client with proper error handling
/// - Returns: The ES client pointer
/// - Throws: EndpointSecurityError for various failure conditions
func createESClientWithLogger() throws -> OpaquePointer {
    let esClientManager = EndpointSecurityClientManager(eventHandler: logger)
    return try esClientManager.createESClient()
}

/// Main application runner with modern concurrency
@MainActor
final class ESClientApplication {
    private var esClient: OpaquePointer?
    
    /// Starts the ES client and waits for termination
    func run() async throws {
        do {
            esClient = try createESClientWithLogger()
            print("[ES CLIENT] Started successfully. Press Ctrl+C to exit.")
            
            // Use a more appropriate approach for waiting indefinitely
            // Create a task that will be cancelled by signal handling
            try await withTaskCancellationHandler {
                try await Task.sleep(for: .seconds(.max))
            } onCancel: {
                Task { @MainActor in
                    self.cleanup()
                }
            }
        } catch {
            print("[ES CLIENT ERROR] \(error.localizedDescription)")
            cleanup()
            throw error
        }
    }
    
    /// Cleanup resources
    func cleanup() {
        if let client = esClient {
            es_delete_client(client)
            esClient = nil
        }
        print("[ES CLIENT] Cleaned up resources")
    }
}

// MARK: - Signal handling for graceful shutdown

/// Shared application instance for signal handling
private var sharedApp: ESClientApplication?

/// Sets up signal handling for graceful shutdown
func setupSignalHandling() {
    let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signalSource.setEventHandler {
        print("\n[ES CLIENT] Received SIGINT, shutting down gracefully...")
        Task { @MainActor in
            sharedApp?.cleanup()
        }
        exit(EXIT_SUCCESS)
    }
    signalSource.resume()
    
    // Ignore the signal so it doesn't terminate the process immediately
    signal(SIGINT, SIG_IGN)
}

// MARK: - Main Entry Point

@main
struct AtomicESClient {
    static func main() async {
        let app = ESClientApplication()
        sharedApp = app
        
        // Set up signal handling for graceful shutdown
        setupSignalHandling()
        
        do {
            try await app.run()
        } catch {
            print("[ES CLIENT FATAL] Application failed: \(error)")
            exit(EXIT_FAILURE)
        }
    }
}
