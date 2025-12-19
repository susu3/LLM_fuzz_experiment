/*
 * OpENer Network Harness for AFLNet-based Fuzzers
 * 
 * This provides a network server that:
 * 1. Listens on port 44818 (EtherNet/IP)
 * 2. Accepts TCP connections
 * 3. Receives packets and feeds them to OpENer's protocol handler
 * 4. Returns responses
 * 
 * This allows OpENer to work with AFLNet, A2, A3, AFL-ICS, ChatAFL
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <signal.h>
#include <errno.h>

// Include OpENer headers
#include "opener_api.h"
#include "doublylinkedlist.h"
#include "cipconnectionobject.h"
#include "enipmessage.h"

#define BUFFER_SIZE 2048
#define DEFAULT_PORT 44818

static int server_fd = -1;
static int client_fd = -1;
static volatile int should_exit = 0;

void signal_handler(int signum) {
    should_exit = 1;
    if (client_fd >= 0) close(client_fd);
    if (server_fd >= 0) close(server_fd);
    exit(0);
}

int main(int argc, char *argv[]) {
    int port = DEFAULT_PORT;
    
    if (argc > 1) {
        port = atoi(argv[1]);
    }
    
    fprintf(stderr, "[Harness] OpENer Network Harness starting on port %d\n", port);
    
    // Setup signal handlers
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGPIPE, SIG_IGN);
    
    // Initialize OpENer stack
    DoublyLinkedListInitialize(&connection_list,
                               CipConnectionObjectListArrayAllocator,
                               CipConnectionObjectListArrayFree);
    
    SetDeviceSerialNumber(123456789);
    EipUint16 unique_connection_id = (EipUint16)rand();
    
    if (CipStackInit(unique_connection_id) != kEipStatusOk) {
        fprintf(stderr, "[Harness] Failed to initialize CIP stack\n");
        return 1;
    }
    
    // Create server socket
    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        fprintf(stderr, "[Harness] Failed to create socket\n");
        return 1;
    }
    
    // Set socket options
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    // Bind to address
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    addr.sin_port = htons(port);
    
    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "[Harness] Failed to bind to port %d: %s\n", port, strerror(errno));
        close(server_fd);
        return 1;
    }
    
    if (listen(server_fd, 5) < 0) {
        fprintf(stderr, "[Harness] Failed to listen\n");
        close(server_fd);
        return 1;
    }
    
    fprintf(stderr, "[Harness] Server listening on 127.0.0.1:%d\n", port);
    
    // Main server loop
    while (!should_exit) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        
        client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            break;
        }
        
        fprintf(stderr, "[Harness] Client connected\n");
        
        // Set receive timeout
        struct timeval tv;
        tv.tv_sec = 5;
        tv.tv_usec = 0;
        setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        
        // Process client requests
        uint8_t buffer[BUFFER_SIZE];
        ssize_t bytes_received;
        
        while ((bytes_received = recv(client_fd, buffer, sizeof(buffer), 0)) > 0) {
            fprintf(stderr, "[Harness] Received %zd bytes\n", bytes_received);
            
            // Process packet with OpENer's handler
            ENIPMessage outgoing_message;
            InitializeENIPMessage(&outgoing_message);
            
            int remaining_bytes = 0;
            EipStatus status = HandleReceivedExplictTcpData(
                client_fd,
                buffer,
                bytes_received,
                &remaining_bytes,
                (struct sockaddr*)&client_addr,
                &outgoing_message
            );
            
            // Send response if generated
            if (outgoing_message.used_message_length > 0) {
                send(client_fd, outgoing_message.message_buffer, 
                     outgoing_message.used_message_length, 0);
                fprintf(stderr, "[Harness] Sent %d bytes response\n", 
                        outgoing_message.used_message_length);
            }
        }
        
        fprintf(stderr, "[Harness] Client disconnected\n");
        close(client_fd);
        client_fd = -1;
    }
    
    signal_handler(0);
    return 0;
}
