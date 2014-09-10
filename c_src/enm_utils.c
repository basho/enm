// -------------------------------------------------------------------
//
// enm_utils.c: misc utilities for nanomsg Erlang language binding
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

#include <string.h>
#include "enm.h"
#include "ei.h"

ErlDrvSSizeT
enm_ok(char* buf)
{
    int index = 0;
    ei_encode_version(buf, &index);
    ei_encode_atom(buf, &index, "ok");
    return index;
}

void
enm_errno_str(int err, char* errstr)
{
    strcpy(errstr, erl_errno_id(err));
    if (strcmp(errstr, "unknown") == 0) {
        switch (err) {
        case EFSM:
            strcpy(errstr, "efsm");
            break;
        case ETERM:
            strcpy(errstr, "eterm");
            break;
        default:
            /* default in case nanomsg adds new errno values
             * not accounted for here */
            strcpy(errstr, "enanomsg");
            break;
        }
    }
}

ErlDrvSSizeT
enm_errno_tuple(char* buf, int err)
{
    int index = 0;
    char errstr[64];

    ei_encode_version(buf, &index);
    ei_encode_tuple_header(buf, &index, 2);
    ei_encode_atom(buf, &index, "error");
    enm_errno_str(err, errstr);
    ei_encode_atom(buf, &index, errstr);
    return ++index;
}

ErlDrvTermData
enm_errno_atom(int err)
{
    char errstr[64];
    enm_errno_str(err, errstr);
    return driver_mk_atom(errstr);
}

static const char* enm_pair = "nnpair";
static const char* enm_req = "nnreq";
static const char* enm_rep = "nnrep";
static const char* enm_bus = "nnbus";
static const char* enm_pub = "nnpub";
static const char* enm_sub = "nnsub";
static const char* enm_push = "nnpush";
static const char* enm_pull = "nnpull";
static const char* enm_svyr = "nnsurveyor";
static const char* enm_resp = "nnrespondent";

const char*
enm_protocol_name(int protocol)
{
    const char* s;

    switch (protocol) {
    case NN_REQ:
    case ENM_REQ:
        s = enm_req;
        break;
    case NN_REP:
    case ENM_REP:
        s = enm_rep;
        break;
    case NN_BUS:
    case ENM_BUS:
        s = enm_bus;
        break;
    case NN_PUB:
    case ENM_PUB:
        s = enm_pub;
        break;
    case NN_SUB:
    case ENM_SUB:
        s = enm_sub;
        break;
    case NN_PUSH:
    case ENM_PUSH:
        s = enm_push;
        break;
    case NN_PULL:
    case ENM_PULL:
        s = enm_pull;
        break;
    case NN_SURVEYOR:
    case ENM_SVYR:
        s = enm_svyr;
        break;
    case NN_RESPONDENT:
    case ENM_RESP:
        s = enm_resp;
        break;
    case NN_PAIR:
    case ENM_PAIR:
        s = enm_pair;
        break;
    }
    return s;
}
