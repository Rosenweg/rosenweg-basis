# SPDX-License-Identifier: GPL-3.0-or-later
# iOS-Teil von rosenweg_basis: Rosenweg-Karte per Core NFC, QR-Code per VisionKit, Geraetekennung.
Pod::Spec.new do |s|
  s.name             = 'rosenweg_basis'
  s.version          = '0.3.0'
  s.summary          = 'Rosenweg-Basis: Anmeldeschirm (Karte, QR) auf iOS'
  s.homepage         = 'https://github.com/Rosenweg/rosenweg-basis'
  s.license          = { :type => 'GPL-3.0-or-later', :file => '../LICENSE' }
  s.author           = { 'Rosenweg 4303' => 'technik@rosenweg4303.ch' }
  s.source           = { :path => '.' }
  s.source_files     = 'rosenweg_basis/Sources/rosenweg_basis/**/*.swift'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'CoreNFC'
  s.weak_frameworks  = 'VisionKit'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
