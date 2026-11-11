//
//  main.swift
//  Pizzinu
//
//  Punto di ingresso dell'applicazione. Il ciclo di vita è gestito da
//  `AppDelegate`; qui si prepara soltanto `NSApplication` e si avvia il ciclo
//  degli eventi.
//

import AppKit

// La sottoclasse annota le eccezioni intercettate da AppKit (ExceptionLog.swift).
let application = PizzinuApplication.shared
ExceptionLog.install()
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()
