//
//  Daemon.swift
//  lnd-gui
//
//  Created by Alex Bosworth on 5/6/17.
//  Copyright © 2017 Adylitica. All rights reserved.
//

import Foundation

struct Daemon {}

extension Daemon {
  enum DeletionResult {
    case error(Error)
    case success
  }
  
  enum GetJsonResult {
    case error(Error)
    case data(Data)
  }
  
  enum SendJsonResult {
    case error(Error)
    case success
  }
  
  enum Api {
    case channels(String)
    case connections
    case paymentRequest(String)
    case payments
    case peers
    case transactions
    
    private var type: String {
      switch self {
      case .channels:
        return "channels"
        
      case .connections:
        return "connections"
        
      case .paymentRequest(_):
        return "payment_request"
        
      case .payments:
        return "payments"
        
      case .peers:
        return "peers"
        
      case .transactions:
        return "transactions"
      }
    }
    
    var url: URL? {
      switch self {
      case .channels(let channelId):
        return URL(string: "http://localhost:10553/v0/\(type)/\(channelId)")
        
      case .connections, .payments, .peers, .transactions:
        return URL(string: "http://localhost:10553/v0/\(type)/")

      case .paymentRequest(let paymentRequest):
        return URL(string: "http://localhost:10553/v0/\(type)/\(paymentRequest)")
      }
    }

    var urlRequest: URLRequest? {
      guard let url = url else { return nil }
      
      let timeoutInterval: TimeInterval = 30
      
      return URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: timeoutInterval)
    }
  }
  
  enum RequestFailure: Error {
    case expectedResponseData
    case expectedUrlRequest
    case expectedValidUrl
  }
  
  enum HttpMethod: String {
    case delete = "DELETE"
    case post = "POST"
    
    var asString: String { return rawValue }
  }
  
  static func delete(in api: Api, completion: @escaping (DeletionResult) -> ()) throws {
    guard let urlRequest = api.urlRequest else { throw RequestFailure.expectedUrlRequest }
    
    let deleteTask = URLSession.shared.dataTask(with: urlRequest) { _, _, error in
      DispatchQueue.main.async {
        if let error = error { return completion(.error(error)) }
        
        completion(.success)
      }
    }
    
    deleteTask.resume()
  }
  
  static func get(from api: Api, completion: @escaping (GetJsonResult) -> ()) throws {
    guard let url = api.url else { throw RequestFailure.expectedValidUrl }
    
    let getJsonTask = URLSession.shared.dataTask(with: URLRequest(url: url)) { data, _, error in
      DispatchQueue.main.async {
        if let error = error { return completion(.error(error)) }
       
        guard let data = data else { return completion(.error(RequestFailure.expectedResponseData)) }
        
        return completion(.data(data))
      }
    }
    
    getJsonTask.resume()
  }
  
  static func send(json: [String: Any], to: Api, completion: @escaping (SendJsonResult) -> ()) throws {
    let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)

    guard var urlRequest = to.urlRequest else { throw RequestFailure.expectedValidUrl }

    urlRequest.httpMethod = HttpMethod.post.asString
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let task = URLSession.shared.uploadTask(with: urlRequest, from: data) { data, urlResponse, error in
      DispatchQueue.main.async {
        if let error = error { return completion(.error(error)) }
        
        return completion(.success)
      }
    }
    
    task.resume()
  }
}

extension Daemon {
  enum AddPeerResult {
    case error(Error)
    case success
  }

  enum AddPeerJsonAttribute: String {
    case host
    case publicKey = "public_key"
    
    var key: String { return rawValue }
  }
  
  static func addPeer(ip: IpAddress, publicKey: PublicKey, completion: @escaping (AddPeerResult) -> ()) throws {
    let json = [AddPeerJsonAttribute.host.key: ip.serialized, AddPeerJsonAttribute.publicKey.key: publicKey.hexEncoded]

    try send(json: json, to: .peers) { result in
      switch result {
      case .error(let error):
        completion(.error(error))
        
      case .success:
        completion(.success)
      }
    }
  }
}