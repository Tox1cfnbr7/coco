# COCO Network Architecture

## Overview

```
Corporate LAN / Home Network
          |
          | 192.168.118.0/24
          |
+---------+---------------------------+
|   Proxmox Host  192.168.118.1      |
|                                    |
|  +------------------------------+  |
|  | COCO Control VM              |  |
|  | 192.168.118.133  <-----------+--+-- Players connect here
|  |                              |  |
|  | Port 8080 : COCO Web-GUI     |  |
|  | Port 8443 : Guacamole        |  |
|  |                              |  |
|  | br-game : 10.10.0.1/16       |  |
|  +----------+-------------------+  |
|             |                      |
|     10.10.0.0/16 (isolated)        |
|     NO route to LAN or Internet    |
|             |                      |
|  +----------+-------------------+  |
|  | VLAN 10 - Active Directory   |  |
|  | 10.10.10.0/24                |  |
|  |   win-dc-01    10.10.10.10   |  |
|  |   win-client   10.10.10.20   |  |
|  |   kali-red     10.10.10.30   |  |
|  +------------------------------+  |
|  | VLAN 20 - Web Application    |  |
|  | 10.10.20.0/24                |  |
|  |   webserver    10.10.20.10   |  |
|  |   kali-red     10.10.20.30   |  |
|  +------------------------------+  |
|  | VLAN 30 - Database           |  |
|  | 10.10.30.0/24                |  |
|  |   db-server    10.10.30.10   |  |
|  |   kali-red     10.10.30.30   |  |
|  +------------------------------+  |
+------------------------------------+
```

## IP Schema

| Network | Range | Purpose |
|---------|-------|---------|
| LAN | 192.168.118.0/24 | Proxmox host + COCO VM reachable |
| Game bridge | 10.10.0.0/16 | All game VLANs — isolated |
| AD Scenario | 10.10.10.0/24 | VLAN 10 |
| Web Application | 10.10.20.0/24 | VLAN 20 |
| Database | 10.10.30.0/24 | VLAN 30 |

## Key Security Rule

Game VMs have NO route to LAN or Internet.
Only the COCO VM bridges both networks via Guacamole.
Players connect to `192.168.118.133` only — game VMs are invisible from outside.

## Traffic Flow

```
Player browser
    --> 192.168.118.133:8080  (COCO Web-GUI)
    --> 192.168.118.133:8443  (Guacamole)
        --> 10.10.x.x         (Game VM via br-game)
```
