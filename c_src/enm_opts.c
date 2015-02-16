// -------------------------------------------------------------------
//
// enm_opts.c: option handling for nanomsg Erlang language binding
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
#include <nanomsg/tcp.h>


static const char* typeopt = "type";
static const char* activeopt = "active";
static const char* rawopt = "raw";
static const char* modeopt = "mode";
static const char* deadlineopt = "deadline";
static const char* subscribeopt = "subscribe";
static const char* unsubscribeopt = "unsubscribe";
static const char* resend_ivl = "resend_ivl";
static const char* sndbuf = "sndbuf";
static const char* rcvbuf = "rcvbuf";
static const char* nodelay = "nodelay";
static const char* ipv4only = "ipv4only";

static const char*
enm_optname(int opt)
{
    switch (opt) {
    case ENM_TYPE:
        return typeopt;
    case ENM_ACTIVE:
        return activeopt;
    case ENM_RAW:
        return rawopt;
    case ENM_BINARY:
        return modeopt;
    case ENM_DEADLINE:
        return deadlineopt;
    case ENM_SUBSCRIBE:
        return subscribeopt;
    case ENM_UNSUBSCRIBE:
        return unsubscribeopt;
    case ENM_RESEND_IVL:
        return resend_ivl;
    case ENM_SNDBUF:
        return sndbuf;
    case ENM_RCVBUF:
        return rcvbuf;
    case ENM_NODELAY:
        return nodelay;
    case ENM_IPV4ONLY:
        return ipv4only;
    default:
        break;
    }
    return 0;
}

ErlDrvSSizeT
enm_getopts(EnmData* d, EnmArgs* args)
{
    ei_x_buff xb;
    int err, optval, rc;
    size_t optlen = sizeof optval;
    const char* optname;

    if (d->fd == -1)
        return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
    ei_x_new_with_version(&xb);
    ei_x_encode_tuple_header(&xb, 2);
    ei_x_encode_atom(&xb, "ok");
    ei_x_encode_list_header(&xb, args->len);
    for (; args->index < args->len; args->index++, args->buf++) {
        if ((optname = enm_optname(*args->buf)) == 0)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        ei_x_encode_tuple_header(&xb, 2);
        ei_x_encode_atom(&xb, optname);
        switch (*args->buf) {
        case ENM_TYPE:
            ei_x_encode_atom(&xb, enm_protocol_name(d->protocol));
            break;
        case ENM_ACTIVE:
            switch (d->b.active) {
            case ENM_TRUE:
                ei_x_encode_atom(&xb, "true");
                break;
            case ENM_FALSE:
                ei_x_encode_atom(&xb, "false");
                break;
            case ENM_ONCE:
                ei_x_encode_atom(&xb, "once");
                break;
            case ENM_N:
                ei_x_encode_long(&xb, d->n_count);
                break;
            }
            break;
        case ENM_RAW:
            ei_x_encode_boolean(&xb, d->b.raw);
            break;
        case ENM_BINARY:
            ei_x_encode_atom(&xb, d->b.listmode ? "list" : "binary");
            break;
        case ENM_DEADLINE:
            if (d->protocol != NN_SURVEYOR) {
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, EINVAL);
            }
            optlen = sizeof optval;
            rc = nn_getsockopt(d->fd, NN_SURVEYOR, NN_SURVEYOR_DEADLINE,
                               &optval, &optlen);
            if (rc < 0) {
                err = errno;
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, err);
            }
            ei_x_encode_long(&xb, optval);
            break;
        case ENM_RESEND_IVL:
            if (d->protocol != NN_REQ) {
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, EINVAL);
            }
            optlen = sizeof args->resend_ivl;
            rc = nn_getsockopt(d->fd, NN_REQ, NN_REQ_RESEND_IVL,
                               &args->resend_ivl, &optlen);
            if (rc < 0) {
                err = errno;
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, err);
            }
            ei_x_encode_ulong(&xb, args->resend_ivl);
            break;
        case ENM_SNDBUF:
            if (d->protocol == NN_PULL || d->protocol == NN_SUB) {
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, EINVAL);
            }
            optlen = sizeof args->sndbuf;
            rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_SNDBUF,
                               &args->sndbuf, &optlen);
            if (rc < 0) {
                err = errno;
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, err);
            }
            ei_x_encode_ulong(&xb, args->sndbuf);
            break;
        case ENM_RCVBUF:
            if (d->protocol == NN_PUSH || d->protocol == NN_PUB) {
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, EINVAL);
            }
            optlen = sizeof args->rcvbuf;
            rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_RCVBUF,
                               &args->rcvbuf, &optlen);
            if (rc < 0) {
                err = errno;
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, err);
            }
            ei_x_encode_ulong(&xb, args->rcvbuf);
            break;
        case ENM_NODELAY:
            optlen = sizeof optval;
            rc = nn_getsockopt(d->fd, NN_TCP, NN_TCP_NODELAY,
                               &optval, &optlen);
            if (rc < 0) {
                err = errno;
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, err);
            }
            ei_x_encode_boolean(&xb, optval);
            break;
        case ENM_IPV4ONLY:
            optlen = sizeof optval;
            rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_IPV4ONLY,
                               &optval, &optlen);
            if (rc < 0) {
                err = errno;
                ei_x_free(&xb);
                return enm_errno_tuple(*args->rbuf, err);
            }
            ei_x_encode_boolean(&xb, optval);
            break;
        default:
            ei_x_free(&xb);
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        }
    }
    ei_x_encode_empty_list(&xb);
    xb.index++;
    if (xb.index <= args->rlen) {
        memcpy(*args->rbuf, xb.buff, xb.index);
    } else {
        ErlDrvBinary* bin = driver_alloc_binary(xb.index);
        memcpy(bin->orig_bytes, xb.buff, xb.index);
        *args->rbuf = (char*)bin;
    }
    args->rlen = xb.index;
    ei_x_free(&xb);
    return args->rlen;
}

ErlDrvSSizeT
enm_setopts_priv(EnmData* d, int opt, EnmArgs* args)
{
    int old_active, rc, optval;
    size_t optlen;

    switch (opt) {
    case ENM_ACTIVE:
        old_active = d->b.active;
        switch (*args->buf) {
        case ENM_TRUE:
        case ENM_FALSE:
        case ENM_ONCE:
            d->b.active = *args->buf++;
            args->index++;
            break;
        case ENM_N:
            d->b.active = *args->buf++;
            d->n_count += (short)GETINT16(args->buf);
            args->buf += 2;
            args->index += 3;
            break;
        default:
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        }
        if (d->fd != -1 && d->b.active != old_active) {
            if (old_active == ENM_N && d->b.active != ENM_N)
                d->n_count = 0;
            if (old_active && !d->b.active && d->rfd != -1)
                enm_read_select(d, 0);
            else if (!old_active && d->b.active && d->fd != -1) {
                rc = enm_read_select(d, 1);
                if (rc < 0)
                    return enm_errno_tuple(*args->rbuf, errno);
            }
        }
        if (d->b.active == ENM_N && d->n_count <= 0) {
            ErlDrvTermData port = driver_mk_port(d->port);
            char pktname[64];
            enm_read_select(d, 0);
            d->b.active = ENM_FALSE;
            d->n_count = 0;
            strcpy(pktname, enm_protocol_name(d->protocol));
            strcat(pktname, "_passive");
            {
                ErlDrvTermData t[] = {
                    ERL_DRV_ATOM, driver_mk_atom(pktname),
                    ERL_DRV_PORT, port,
                    ERL_DRV_TUPLE, 2,
                };
                erl_drv_output_term(port, t, sizeof t/sizeof *t);
            }
        }
        break;
    case ENM_RAW:
        d->b.raw = *args->buf++;
        args->index++;
        break;
    case ENM_BINARY:
        d->b.listmode = (*args->buf++ == ENM_FALSE);
        args->index++;
        break;
    case ENM_DEADLINE:
        if (d->protocol != NN_SURVEYOR)
            return enm_errno_tuple(*args->rbuf, EINVAL);
        args->deadline = (int)GETINT32(args->buf);
        if (args->deadline <= 0)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_SURVEYOR, NN_SURVEYOR_DEADLINE,
                               &args->deadline, sizeof args->deadline);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf += 4;
        args->index += 4;
        break;
    case ENM_SUBSCRIBE:
        if (d->protocol != NN_SUB)
            return enm_errno_tuple(*args->rbuf, EINVAL);
        args->b.topic_seen = 1;
        strcpy(args->topic, args->buf);
        optlen = strlen(args->topic);
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_SUB, NN_SUB_SUBSCRIBE,
                               args->topic, optlen);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf += optlen+1;
        args->index += optlen+1;
        break;
    case ENM_UNSUBSCRIBE:
        if (d->protocol != NN_SUB)
            return enm_errno_tuple(*args->rbuf, EINVAL);
        strcpy(args->topic, args->buf);
        optlen = strlen(args->topic);
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_SUB, NN_SUB_UNSUBSCRIBE,
                               args->topic, optlen);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf += optlen+1;
        args->index += optlen+1;
        break;
    case ENM_RESEND_IVL:
        if (d->protocol != NN_REQ)
            return enm_errno_tuple(*args->rbuf, EINVAL);
        args->resend_ivl = (int)GETINT32(args->buf);
        if (args->resend_ivl <= 0)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_REQ, NN_REQ_RESEND_IVL,
                               &args->resend_ivl, sizeof args->resend_ivl);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf += 4;
        args->index += 4;
        break;
    case ENM_SNDBUF:
        if (d->protocol == NN_PULL || d->protocol == NN_SUB)
            return enm_errno_tuple(*args->rbuf, EINVAL);
        args->sndbuf = (int)GETINT32(args->buf);
        if (args->sndbuf <= 0)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_SOL_SOCKET, NN_SNDBUF,
                               &args->sndbuf, sizeof args->sndbuf);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf += 4;
        args->index += 4;
        break;
    case ENM_RCVBUF:
        if (d->protocol == NN_PUSH || d->protocol == NN_PUB)
            return enm_errno_tuple(*args->rbuf, EINVAL);
        args->rcvbuf = (int)GETINT32(args->buf);
        if (args->rcvbuf <= 0)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_SOL_SOCKET, NN_RCVBUF,
                               &args->rcvbuf, sizeof args->rcvbuf);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf += 4;
        args->index += 4;
        break;
    case ENM_NODELAY:
        optval = *args->buf;
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_TCP, NN_TCP_NODELAY,
                               &optval, sizeof optval);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf++;
        args->index++;
        break;
    case ENM_IPV4ONLY:
        optval = *args->buf;
        if (d->fd != -1) {
            rc = nn_setsockopt(d->fd, NN_SOL_SOCKET, NN_IPV4ONLY,
                               &optval, sizeof optval);
            if (rc < 0)
                return enm_errno_tuple(*args->rbuf, errno);
        }
        args->buf++;
        args->index++;
        break;
    default:
        return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
    }
    return 0;
}

ErlDrvSSizeT
enm_setopts(EnmData* d, EnmArgs* args)
{
    ErlDrvSSizeT res;
    int opt;

    if (d->fd == -1)
        return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
    while (args->index < args->len) {
        opt = *args->buf++;
        args->index++;
        switch (opt) {
        case ENM_ACTIVE:
        case ENM_BINARY:
        case ENM_DEADLINE:
        case ENM_SUBSCRIBE:
        case ENM_UNSUBSCRIBE:
        case ENM_RESEND_IVL:
        case ENM_SNDBUF:
        case ENM_RCVBUF:
        case ENM_NODELAY:
        case ENM_IPV4ONLY:
            if ((res = enm_setopts_priv(d, opt, args)) != 0)
                return res;
            break;
        default:
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        }
    }
    return enm_ok(*args->rbuf);
}
