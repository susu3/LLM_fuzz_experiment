//
// EtherNet/IP Server for Vulnerability Verification
// Simplified version of EIPServerHarness without coverage/fuzzing overhead
//

#include <iostream>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <vector>
#include <signal.h>
#include <atomic>

// EIPScanner headers
#include "eip/EncapsPacket.h"
#include "eip/EncapsPacketFactory.h"
#include "eip/CommonPacket.h"
#include "eip/CommonPacketItem.h"
#include "eip/CommonPacketItemFactory.h"
#include "utils/Logger.h"
#include "utils/Buffer.h"

using namespace eipScanner;
using namespace eipScanner::eip;
using namespace eipScanner::cip;
using namespace eipScanner::utils;

const int MAX_BUFFER_SIZE = 65536;
const int BACKLOG = 5;

// Global flag for graceful shutdown
std::atomic<bool> g_running(true);

// Signal handler
void signal_handler(int signum) {
    std::cout << "\n[!] Received signal " << signum << ", shutting down..." << std::endl;
    g_running = false;
}

int main(int argc, char* argv[]) {
    int port = 44818;
    if (argc > 1) {
        port = std::atoi(argv[1]);
    }
    
    // Set logging to INFO to see parsing details
    Logger::setLogLevel(LogLevel::INFO);
    
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    
    // 1. Setup Server Socket
    int server_sock = socket(AF_INET, SOCK_STREAM, 0);
    if (server_sock < 0) {
        std::cerr << "[-] Failed to create socket" << std::endl;
        return 1;
    }
    
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(port);
    
    if (bind(server_sock, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        std::cerr << "[-] Bind failed on port " << port << std::endl;
        close(server_sock);
        return 1;
    }
    
    if (listen(server_sock, BACKLOG) < 0) {
        std::cerr << "[-] Listen failed" << std::endl;
        close(server_sock);
        return 1;
    }
    
    std::cout << "[+] EIPScanner Vulnerability Verification Server started on port " << port << std::endl;
    std::cout << "[+] Waiting for connections..." << std::endl;
    
    // 2. Main Loop
    while (g_running) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_sock = accept(server_sock, (struct sockaddr*)&client_addr, &client_len);
        
        if (client_sock < 0) {
            if (g_running) std::cerr << "[-] Accept error: " << strerror(errno) << std::endl;
            continue;
        }
        
        std::cout << "\n[+] Accepted connection from " << inet_ntoa(client_addr.sin_addr) << std::endl;
        
        // Read data
        std::vector<uint8_t> buffer(MAX_BUFFER_SIZE);
        ssize_t bytes_received = recv(client_sock, buffer.data(), MAX_BUFFER_SIZE, 0);
        
        if (bytes_received > 0) {
            std::cout << "[+] Received " << bytes_received << " bytes" << std::endl;
            
            // 3. Call EIPScanner Library (The Target)
            try {
                std::vector<uint8_t> recv_data(buffer.begin(), buffer.begin() + bytes_received);
                EncapsPacket request_packet;
                
                std::cout << "[*] Calling EncapsPacket::expand()..." << std::endl;
                // VULNERABILITY TARGET 1: Encapsulation Header Parsing
                request_packet.expand(recv_data);
                
                std::cout << "[+] Encapsulation Header parsed successfully" << std::endl;
                std::cout << "    Command: 0x" << std::hex << static_cast<int>(request_packet.getCommand()) << std::endl;
                std::cout << "    Length:  " << std::dec << request_packet.getLength() << std::endl;
                
                // Deep parsing for specific commands
                if (request_packet.getCommand() == EncapsCommands::SEND_RR_DATA ||
                    request_packet.getCommand() == EncapsCommands::SEND_UNIT_DATA) {
                    
                    std::cout << "[*] Calling CommonPacket::expand()..." << std::endl;
                    // VULNERABILITY TARGET 2: CIP Payload Parsing
                    CommonPacket commonPacket;
                    commonPacket.expand(request_packet.getData());
                    
                    std::cout << "[+] CIP CommonPacket parsed successfully" << std::endl;
                    std::cout << "    Item Count: " << commonPacket.getItems().size() << std::endl;
                }
                
                // Construct Response
                EncapsPacket response_packet;
                response_packet.setCommand(request_packet.getCommand());
                response_packet.setSessionHandle(request_packet.getSessionHandle());
                response_packet.setStatusCode(EncapsStatusCodes::SUCCESS);
                
                std::vector<uint8_t> response_data = response_packet.pack();
                send(client_sock, response_data.data(), response_data.size(), 0);
                std::cout << "[+] Sent SUCCESS response" << std::endl;
                
            } catch (const std::exception& e) {
                std::cerr << "[-] Parsing Exception: " << e.what() << std::endl;
                
                // Send Error Response
                try {
                    EncapsPacket response_packet;
                    // Try to extract command from raw buffer if possible
                    CipUint cmd = (bytes_received >= 2) ? (buffer[0] | (buffer[1] << 8)) : 0;
                    response_packet.setCommand(static_cast<EncapsCommands>(cmd));
                    response_packet.setStatusCode(EncapsStatusCodes::INVALID_FORMAT_OR_DATA);
                    
                    std::vector<uint8_t> response_data = response_packet.pack();
                    send(client_sock, response_data.data(), response_data.size(), 0);
                    std::cout << "[+] Sent ERROR response" << std::endl;
                } catch (...) {
                    std::cerr << "[-] Failed to send error response" << std::endl;
                }
            } catch (...) {
                std::cerr << "[-] Unknown Exception occurred" << std::endl;
            }
        }
        
        close(client_sock);
        std::cout << "[+] Connection closed" << std::endl;
    }
    
    close(server_sock);
    return 0;
}
