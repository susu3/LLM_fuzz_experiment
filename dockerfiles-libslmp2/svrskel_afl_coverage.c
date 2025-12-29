/*
 * Coverage-friendly SLMP Server based on libslmp2
 * 
 * This version accepts multiple connections for coverage analysis,
 * unlike the AFL version which is one-shot.
 */

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <signal.h>

#include "slmp/slmp.h"
#include "slmp/slmperr.h"
#include "slmp/command/cmdcode.h"
#include "slmp/command/selftest.h"

/* Global flag for graceful shutdown */
static volatile int keep_running = 1;

void signal_handler(int signo) {
    if (signo == SIGTERM || signo == SIGINT) {
        fprintf(stderr, "DEBUG: Received signal %d, shutting down gracefully...\n", signo);
        keep_running = 0;
    }
}

/* Loopback test command handler */
static int on_loopback_test(slmp_server_trx_info_t* info, void* userptr)
{
    int hint = SLMP_SERVER_HINT_SKIP;
    slmp_req_self_test_t *req = (slmp_req_self_test_t*)(info->req_cmd);
    size_t res_size;
    slmp_res_self_test_t *res = NULL;
    slmp_frame_t *resp_frame = NULL;
    size_t data_len;

    if (req == NULL) {
        goto __done;
    }

    res_size = sizeof(slmp_res_self_test_t) + req->len - 1;
    res = (slmp_res_self_test_t*)calloc(1, res_size);
    if (res == NULL) {
        goto __done;
    }

    res->hdr.addr_width = SLMP_ADDRESS_WIDTH_DONT_CARE;
    res->hdr.size = res_size;
    res->len = req->len;
    memcpy(res->data, req->data, req->len);

    data_len = slmp_encode_res_self_test((slmp_cmd_hdr_t*)res, NULL,
        info->strm_type);
    resp_frame = slmp_calloc(1, SLMP_FRAME_STRUCT_SIZE(data_len));
    if (resp_frame == NULL) {
        goto __done;
    }

    switch (info->cat) {
    case SLMP_FRAME_CATEGORY_ST:
        resp_frame->hdr.ftype = SLMP_FTYPE_RES_ST;
        resp_frame->cmd_data.st.cmd = SLMP_CMD_LOOPBACK_TEST;
        resp_frame->sub_hdr.st.net_no = info->req_frame->sub_hdr.st.net_no;
        resp_frame->sub_hdr.st.node_no = info->req_frame->sub_hdr.st.node_no;
        resp_frame->sub_hdr.st.dst_proc_no = info->req_frame->sub_hdr.st.dst_proc_no;
        resp_frame->sub_hdr.st.data_len = (uint16_t)data_len;
        break;
    case SLMP_FRAME_CATEGORY_MT:
        resp_frame->hdr.ftype = SLMP_FTYPE_RES_MT;
        resp_frame->cmd_data.mt.cmd = SLMP_CMD_LOOPBACK_TEST;
        resp_frame->sub_hdr.mt.net_no = info->req_frame->sub_hdr.mt.net_no;
        resp_frame->sub_hdr.mt.node_no = info->req_frame->sub_hdr.mt.node_no;
        resp_frame->sub_hdr.mt.dst_proc_no = info->req_frame->sub_hdr.mt.dst_proc_no;
        resp_frame->sub_hdr.mt.data_len = (uint16_t)data_len;
        break;
    default:
        goto __done;
    }

    resp_frame->size = SLMP_FRAME_STRUCT_SIZE(data_len);

    if (slmp_encode_res_self_test((slmp_cmd_hdr_t*)res, resp_frame->raw_data, 
        info->strm_type) != data_len)
    {
        goto __done;
    }

    info->resp_frame = resp_frame;
    hint = SLMP_SERVER_HINT_CONTINUE;

__done:
    free(res);
    return hint;
}

/* Command dispatch table */
SLMP_SERVER_BEGIN_COMMAND_DISPATCH_TABLE(const static, disp_tbl)
    SLMP_SERVER_COMMAND_DISPATCH(
        SLMP_CMD_LOOPBACK_TEST, 0x0000, 
        SLMP_ADDRESS_WIDTH_DONT_CARE, 
        slmp_decode_req_self_test, on_loopback_test)
SLMP_SERVER_END_COMMAND_DISPATCH_TABLE()

/* Helper function to find command dispatch entry */
static const slmp_server_cmd_disp_entry_t* lookup_cmd_disp_entry(
    uint16_t cmd, uint16_t subcmd)
{
    const slmp_server_cmd_disp_entry_t *entry = disp_tbl;
    
    while (entry->handler != NULL) {
        if (entry->cmd == cmd && entry->subcmd == subcmd) {
            return entry;
        }
        entry++;
    }
    return NULL;
}

/* Helper to get frame category */
static int get_frame_category(slmp_frame_t *frame) {
    switch (frame->hdr.ftype) {
    case SLMP_FTYPE_REQ_ST:
    case SLMP_FTYPE_RES_ST:
    case SLMP_FTYPE_ERR_ST:
        return SLMP_FRAME_CATEGORY_ST;
    case SLMP_FTYPE_REQ_MT:
    case SLMP_FTYPE_RES_MT:
    case SLMP_FTYPE_ERR_MT:
        return SLMP_FRAME_CATEGORY_MT;
    default:
        return -1;
    }
}

/* Process one connection */
static void process_connection(slmp_pktio_t *pktio) {
    int strm_type = SLMP_BINARY_STREAM;
    
    fprintf(stderr, "DEBUG: Processing new connection\n");
    
    /* Process requests on this connection until it closes */
    while (keep_running) {
        slmp_frame_t *frame = NULL;
        size_t n;
        
        /* Receive one frame */
        n = slmp_receive_frames(pktio, &frame, 1, &strm_type, 1000);  // 1 second timeout
        if (n != 1 || frame == NULL) {
            if (!keep_running) {
                fprintf(stderr, "DEBUG: Shutting down\n");
                break;
            }
            /* Connection closed or timeout */
            int err = slmp_get_errno();
            if (err == SLMP_ERROR_TIMEOUT) {
                // Just a timeout, continue
                continue;
            }
            fprintf(stderr, "DEBUG: Connection closed or error, errno=%d\n", err);
            break;
        }
        
        /* Find command handler */
        const slmp_server_cmd_disp_entry_t *cmd_disp = 
            lookup_cmd_disp_entry(frame->cmd_data.st.cmd, frame->cmd_data.st.sub_cmd);
        
        if (cmd_disp == NULL) {
            slmp_free(frame);
            continue;
        }
        
        /* Decode command */
        slmp_cmd_hdr_t *cmd = NULL;
        if (cmd_disp->decode != NULL) {
            cmd = cmd_disp->decode(frame->raw_data, SLMP_FRAME_RAW_DATA_SIZE(frame),
                strm_type, cmd_disp->addr_width);
        }
        
        /* Prepare transaction info */
        slmp_server_trx_info_t trx_info = { 0 };
        trx_info.strm_type = strm_type;
        trx_info.cat = get_frame_category(frame);
        trx_info.req_frame = frame;
        trx_info.req_cmd = cmd;
        trx_info.resp_frame = NULL;
        
        /* Call handler */
        if (cmd_disp->handler != NULL) {
            cmd_disp->handler(&trx_info, NULL);
        }
        
        /* Send response if generated */
        if (trx_info.resp_frame != NULL) {
            slmp_send_frames(pktio, &(trx_info.resp_frame), 1, strm_type, 0);
            slmp_free(trx_info.resp_frame);
        }
        
        /* Cleanup */
        slmp_free(cmd);
        slmp_free(frame);
    }
    
    fprintf(stderr, "DEBUG: Connection processing complete\n");
}

int main(int argc, char *argv[])
{
    int port = 8888;
    slmp_pktio_t *pktio = NULL;
    
    /* Setup signal handlers */
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    
    /* Get port from command line */
    if (argc >= 2) {
        port = atoi(argv[1]);
        if (port <= 0 || port > 65535) port = 8888;
    }
    
    fprintf(stderr, "DEBUG: Starting SLMP coverage server on port %d\n", port);
    
    /* Create packet I/O for server */
    pktio = slmp_pktio_new_tcpip(SLMP_PKTIO_SERVER, "0.0.0.0", port);
    if (pktio == NULL) {
        fprintf(stderr, "ERROR: Failed to create packet I/O\n");
        return -1;
    }
    
    /* Set timeouts */
    slmp_pktio_tcpip_set_accept_timeout(pktio, 1);  // 1 second accept timeout
    slmp_pktio_tcpip_set_recv_timeout(pktio, 1);    // 1 second recv timeout
    
    /* Open (bind and listen) */
    if (slmp_pktio_open(pktio) != 0) {
        fprintf(stderr, "ERROR: Failed to open/bind server\n");
        slmp_pktio_free(pktio);
        return -1;
    }
    
    fprintf(stderr, "DEBUG: Server bound and listening\n");
    
    /* Accept and process multiple connections */
    while (keep_running) {
        /* Accept one connection */
        int ret = slmp_pktio_accept(pktio);
        if (ret != 0) {
            if (!keep_running) {
                break;
            }
            /* Timeout or error, continue */
            int err = slmp_get_errno();
            if (err == SLMP_ERROR_TIMEOUT) {
                continue;  // Just a timeout, keep waiting
            }
            fprintf(stderr, "DEBUG: Accept failed, errno=%d\n", err);
            continue;
        }
        
        /* Process this connection */
        process_connection(pktio);
        
        /* Connection is closed by the client or timeout, ready for next accept */
    }
    
    /* Cleanup */
    fprintf(stderr, "DEBUG: Shutting down server\n");
    slmp_pktio_close(pktio);
    slmp_pktio_free(pktio);
    
    return 0;
}

