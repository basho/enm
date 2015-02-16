#ifndef ENM_C_SRC_ENM_H
#define ENM_C_SRC_ENM_H

// -------------------------------------------------------------------
//
// enm.h: common definitions for nanomsg Erlang language binding
//
// Copyright (c) 2014 Basho Technologies, Inc. All Rights Reserved.
//
// This file is provided to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file
// except in compliance with the License.  You may obtain
// a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.
//
// -------------------------------------------------------------------

#include "nanomsg/nn.h"
#include "nanomsg/reqrep.h"
#include "nanomsg/bus.h"
#include "nanomsg/pubsub.h"
#include "nanomsg/pipeline.h"
#include "nanomsg/survey.h"
#include "nanomsg/pair.h"
#include "erl_driver.h"
#include "ei.h"

#define ENM_CLOSE       1
#define ENM_BIND        2
#define ENM_CONNECT     3
#define ENM_SHUTDOWN    4
#define ENM_TERM        5
#define ENM_RECV        10
#define ENM_CANCEL_RECV 11
#define ENM_GETOPTS     12
#define ENM_SETOPTS     13
#define ENM_REQ         20
#define ENM_REP         21
#define ENM_BUS         22
#define ENM_PUB         23
#define ENM_SUB         24
#define ENM_PUSH        25
#define ENM_PULL        26
#define ENM_SVYR        27
#define ENM_RESP        28
#define ENM_PAIR        29

#define ENM_FALSE       0
#define ENM_TRUE        1
#define ENM_ONCE        2
#define ENM_N           3
#define ENM_ACTIVE      10
#define ENM_TYPE        11
#define ENM_RAW         12
#define ENM_DEADLINE    13
#define ENM_SUBSCRIBE   14
#define ENM_UNSUBSCRIBE 15
#define ENM_RESEND_IVL  16
#define ENM_BINARY      17
#define ENM_SNDBUF      18
#define ENM_RCVBUF      19
#define ENM_NODELAY     20
#define ENM_IPV4ONLY    21

#define IDXSHFT(P,I,SH) ((int)(((unsigned char)((P)[I]))<<(SH)))
#define GETINT16(P) (IDXSHFT(P,0,8) | IDXSHFT(P,1,0))
#define GETINT32(P) (IDXSHFT(P,0,24) | IDXSHFT(P,1,16) | \
                     IDXSHFT(P,2,8) | IDXSHFT(P,3,0))

typedef struct EnmRecv {
    ErlDrvMonitor monitor;
    erlang_ref ref;
    ErlDrvTermData rcvr;
    struct EnmRecv* next;
} EnmRecv;

typedef struct {
    ErlDrvPort port;
    EnmRecv* waiting_recvs;
    size_t busy_limit;
    int protocol;
    int fd;
    int sfd;
    int rfd;
    short n_count;
    struct {
        unsigned active:     2;
        unsigned raw:        1;
        unsigned listmode:   1;
        unsigned writable:   1;
        unsigned write_poll: 1;
        unsigned read_poll:  1;
        unsigned busy:       1;
    } b;
} EnmData;

#define ENM_MAX_TOPIC 256

typedef struct {
    char topic[ENM_MAX_TOPIC];
    char* buf;
    char** rbuf;
    int len;
    int index;
    int rlen;
    int deadline;
    int resend_ivl;
    int sndbuf;
    int rcvbuf;
    struct {
        unsigned topic_seen: 1;
    } b;
}  EnmArgs;

extern int enm_write_select(EnmData* d, int start);
extern int enm_read_select(EnmData* d, int start);
extern ErlDrvSSizeT enm_getopts(EnmData* d, EnmArgs* args);
extern ErlDrvSSizeT enm_setopts_priv(EnmData* d, int opt, EnmArgs* args);
extern ErlDrvSSizeT enm_setopts(EnmData* d, EnmArgs* args);
extern ErlDrvSSizeT enm_ok(char* buf);
extern void enm_errno_str(int err, char* errstr);
extern ErlDrvSSizeT enm_errno_tuple(char* buf, int err);
extern ErlDrvTermData enm_errno_atom(int err);
extern const char* enm_protocol_name(int protocol);

#endif
