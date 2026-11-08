//
//  main.swift
//  Pizzinu
//
//  Punto di ingresso dell'applicazione. Il ciclo di vita è gestito da
//  `AppDelegate`; qui si prepara soltanto `NSApplication` e si avvia il ciclo
//  degli eventi.
//

import AppKit

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
