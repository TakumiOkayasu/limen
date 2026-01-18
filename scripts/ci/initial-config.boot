interfaces {
    ethernet eth0 {
        address 192.168.1.1/24
        description "LAN (Initial Config)"
    }
}
service {
    ssh {
        listen-address 192.168.1.1
        port 22
    }
}
system {
    config-management {
        commit-revisions 100
    }
    console {
        device ttyS0 {
            speed 115200
        }
    }
    host-name vyos
    login {
        user vyos {
            authentication {
                encrypted-password "$6$rounds=656000$YkU4zVPMSb9mPxr.$0sRe0sSOcNbnTGpNxG6l1sWP6DxZqDf8p7PcT6T7RUkZHCr8s5EJ0FNxDXTxHLNlNl4/KhFy.pYJz0C8JzZ6w1"
                plaintext-password ""
            }
            level admin
        }
    }
    syslog {
        global {
            facility all {
                level info
            }
            facility protocols {
                level debug
            }
        }
    }
    time-zone Asia/Tokyo
}

// VyOS built-in feature
// =============================================
// This is the initial configuration for VyOS custom ISO
// After installation, run driver-check to verify network drivers:
//   driver-check
// =============================================
