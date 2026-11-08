//
//  PizzinuLog.swift
//  PizzinuKit
//
//  Log diagnostico. Non registra mai il testo delle note: solo eventi,
//  identificatori e metriche.
//

import Foundation
import os

public enum PizzinuLog {
    private static let subsystem = "it.pizzinu.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let windows = Logger(subsystem: subsystem, category: "windows")
    public static let transfer = Logger(subsystem: subsystem, category: "transfer")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
}
