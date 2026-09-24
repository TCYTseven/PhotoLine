//
//  AuthFactory.swift
//  Authentication
//
//


import Foundation
import Factory
import Common


public extension Container {
    /// Full auth repository (sign-in, sign-out, account deletion).
    var authRepository: Factory<AuthRepository> {
        self { AuthRepositoryImpl() }
    }
}

extension Container {
    var authRemoteDataSource: Factory<AuthRemoteDataSource> {
        self { AuthRemoteDataSourceImpl() }
    }

    var authLocalDataSource: Factory<AuthLocalDataSource> {
        self { AuthLocalDataSourceImpl() }
    }

    var appleAuthProvider: Factory<AppleAuthProvider> {
        self { AppleAuthProviderImpl() }
    }
}

public extension Container {
    var authStatusRepository: Factory<AuthStatusRepository> {
        self { AuthStatusRepositoryImpl(authRepository: self.authRepository()) }
    }
}
