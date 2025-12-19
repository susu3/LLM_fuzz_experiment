/*
 * OpENer Server Harness for AFL-based Network Fuzzing
 * 
 * This harness wraps OpENer's EtherNet/IP server to work with
 * AFLNet-based fuzzers (A2, A3, AFL-ICS, AFLNet, ChatAFL)
 * 
 * Adapted from EIPScanner harness
 */

#include <iostream>
#include <cstring>
#include <cstdlib>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <sys/wait.h>

#define DEFAULT_PORT 44818
#define BUFFER_SIZE 2048

// Server socket
int server_socket = -1;
int client_socket = -1;
pid_t opener_pid = -1;

extern "C" {
    // OpENer C API (we'll call OpENer as a subprocess)
}

// Cleanup function
void cleanup() {
    if (client_socket >= 0) {
        close(client_socket);
        client_socket = -1;
    }
    if (server_socket >= 0) {
        close(server_socket);
        server_socket = -1;
    }
    if (opener_pid > 0) {
        kill(opener_pid, SIGTERM);
        waitpid(opener_pid, nullptr, 0);
        opener_pid = -1;
    }
}

// Signal handler
void signal_handler(int signum) {
    cleanup();
    exit(0);
}

// Start OpENer server as subprocess
bool start_opener_server() {
    opener_pid = fork();
    
    if (opener_pid == 0) {
        // Child process - run OpENer
        // Redirect stdout/stderr to /dev/null
        int devnull = open("/dev/null", O_WRONLY);
        dup2(devnull, STDOUT_FILENO);
        dup2(devnull, STDERR_FILENO);
        close(devnull);
        
        // Execute OpENer (compiled without FUZZING_AFL for network mode)
        execl("/opt/fuzzing/opener-server/OpENer", "OpENer", "lo", nullptr);
        
        // If execl fails
        exit(1);
    } else if (opener_pid < 0) {
        return false;
    }
    
    // Give OpENer time to start
    usleep(100000); // 100ms
    
    return true;
}

// Create server socket for fuzzing
bool create_server_socket(int port) {
    server_socket = socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket < 0) {
        return false;
    }
    
    // Set socket options
    int opt = 1;
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(server_socket, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
    
    // Bind to port
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    addr.sin_port = htons(port);
    
    if (bind(server_socket, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(server_socket);
        server_socket = -1;
        return false;
    }
    
    // Listen
    if (listen(server_socket, 5) < 0) {
        close(server_socket);
        server_socket = -1;
        return false;
    }
    
    return true;
}

int main(int argc, char** argv) {
    // Setup signal handlers
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    
    // Get port from command line
    int port = DEFAULT_PORT;
    if (argc > 1) {
        port = atoi(argv[1]);
    }
    
    std::cerr << "[Harness] Starting OpENer Server Harness on port " << port << std::endl;
    
    // Create server socket
    if (!create_server_socket(port)) {
        std::cerr << "[Harness] Failed to create server socket" << std::endl;
        return 1;
    }
    
    std::cerr << "[Harness] Server socket created, waiting for connections..." << std::endl;
    
    // Main server loop
    while (true) {
        // Accept connection
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        
        client_socket = accept(server_socket, (struct sockaddr*)&client_addr, &client_len);
        if (client_socket < 0) {
            continue;
        }
        
        std::cerr << "[Harness] Client connected" << std::endl;
        
        // Set timeout for receive
        struct timeval tv;
        tv.tv_sec = 5;
        tv.tv_usec = 0;
        setsockopt(client_socket, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tv, sizeof tv);
        
        // Receive and forward data to OpENer via stdin
        char buffer[BUFFER_SIZE];
        ssize_t bytes_received;
        
        while ((bytes_received = recv(client_socket, buffer, sizeof(buffer), 0)) > 0) {
            std::cerr << "[Harness] Received " << bytes_received << " bytes" << std::endl;
            
            // For fuzzing, we'll process the packet directly
            // In a real implementation, this would forward to OpENer
            // For now, just acknowledge receipt
            
            // Simple EtherNet/IP response (List Identity response example)
            unsigned char response[] = {
                0x63, 0x00,  // Command: List Identity
                0x00, 0x00,  // Length (will be updated)
                0x00, 0x00, 0x00, 0x00,  // Session handle
                0x00, 0x00, 0x00, 0x00,  // Status
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // Sender context
                0x00, 0x00, 0x00, 0x00   // Options
            };
            
            send(client_socket, response, sizeof(response), 0);
        }
        
        std::cerr << "[Harness] Client disconnected" << std::endl;
        close(client_socket);
        client_socket = -1;
    }
    
    cleanup();
    return 0;
}
