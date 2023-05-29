//
//  VaporApplicationEx.swift
//  
//
//  Created by Ido on 08/02/2023.
//

import Foundation
import Vapor
import DSLogger
import MNUtils

fileprivate let dlog : DSLogger? = DLog.forClass("VaporApplicationEx")

typealias MigrationResult = AppResult<[String]>

fileprivate let MIN_REQUIRED_TABLE_NAMES = ["brick", "person", "buser", "access_token", "app_role", "brick_basic_info", "company"]


extension Vapor.Application /* Bricks */{
    
    /// Will validate migration by checking that all tablenames returns the minimum table names needed to run.
    /// - Returns: void when success or an error when failed
    func validateMigration() throws->EventLoopFuture<MigrationResult> {
        var result = DBActions.postgres.allTableNames(db: self.db, ignoreFluentTables: true)
        switch result {
        case .success(let names):
            
            // Check resulting DB table names:
            if !names.contains(allOf: MIN_REQUIRED_TABLE_NAMES, isCaseSensitive: false) {
                dlog?.warning("validateMigration() Missing table names: \(MIN_REQUIRED_TABLE_NAMES.removing(objects: names).descriptionsJoined)")
                throw AppError(code:.db_failed_init, reason: "Some required table names are missing")
            } else {
                result = .success(["Table names ✔"])
            }
            // to do More tests?
            
        case .failure(let error):
            throw error // no names or error fetching from db!
        }
        
        // Next
        let evloop = self.eventLoopGroup.next()
        return result.asEventLoppFuture(for: evloop)
    }
}