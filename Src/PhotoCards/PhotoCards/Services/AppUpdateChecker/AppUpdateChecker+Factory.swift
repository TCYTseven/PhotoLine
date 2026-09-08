//
//  AppUpdateChecker+Factory.swift
//  PhotoCards
//
//  Created by Claude on 1/1/26.
//

import Factory

public extension Container {
    var appUpdateChecker: Factory<AppUpdateChecker> {
        self { AppUpdateChecker() }.singleton
    }
}
