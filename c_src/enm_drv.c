// -------------------------------------------------------------------
//
// enm_drv.c: driver entry points for nanomsg Erlang language binding
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

#include <sys/resource.h>
#include <errno.h>
#include <string.h>
#include <assert.h>
#include "enm.h"

#define ENM_REFS_EQUAL(R1,R2) \
    (strcmp((R1).node, (R2).node) == 0 && \
     (R1).len == (R2).len && memcmp((R1).n, (R2).n, (R1).len) == 0)

static EnmData** enm_sockets;

static int
enm_cmd_to_protocol(int cmd)
{
    switch (cmd) {
    case ENM_REQ:
        return NN_REQ;
    case ENM_REP:
        return NN_REP;
    case ENM_BUS:
        return NN_BUS;
    case ENM_PUB:
        return NN_PUB;
    case ENM_SUB:
        return NN_SUB;
    case ENM_PUSH:
        return NN_PUSH;
    case ENM_PULL:
        return NN_PULL;
    case ENM_SVYR:
        return NN_SURVEYOR;
    case ENM_RESP:
        return NN_RESPONDENT;
    case ENM_PAIR:
        return NN_PAIR;
    default:
        errno = ENOPROTOOPT;
        return -1;
    }
}

static ErlDrvTermData
enm_protocol_atom(int protocol)
{
    return driver_mk_atom((char*)enm_protocol_name(protocol));
}

int
enm_write_select(EnmData* d, int start)
{
    ErlDrvEvent event;
    int rc;
    size_t optlen = sizeof d->sfd;

    if (start) {
        if (d->b.write_poll)
            return 0;
        if (d->sfd == -1) {
            if (d->protocol == NN_PULL || d->protocol == NN_SUB) {
                errno = EINVAL;
                return -1;
            }
            rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_SNDFD, &d->sfd, &optlen);
            if (rc < 0)
                return -1;
            enm_sockets[d->sfd] = d;
        }
        event = (ErlDrvEvent)(long)d->sfd;
        driver_select(d->port, event, ERL_DRV_WRITE|ERL_DRV_USE, 1);
        d->b.write_poll = 1;
    } else {
        if (!d->b.write_poll)
            return 0;
        assert(d->sfd != -1);
        event = (ErlDrvEvent)(long)d->sfd;
        driver_select(d->port, event, ERL_DRV_WRITE|ERL_DRV_USE, 0);
        d->b.write_poll = 0;
    }
    return 0;
}

int
enm_read_select(EnmData* d, int start)
{
    ErlDrvEvent event;
    int rc;
    size_t optlen = sizeof d->rfd;

    if (start) {
        if (d->b.read_poll)
            return 0;
        if (d->rfd == -1) {
            if (d->protocol == NN_PUSH) {
                errno = EINVAL;
                return -1;
            }
            rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_RCVFD, &d->rfd, &optlen);
            if (rc < 0)
                return -1;
            enm_sockets[d->rfd] = d;
        }
        event = (ErlDrvEvent)(long)d->rfd;
        driver_select(d->port, event, ERL_DRV_READ|ERL_DRV_USE, 1);
        d->b.read_poll = 1;
    } else {
        if (!d->b.read_poll)
            return 0;
        assert(d->rfd != -1);
        event = (ErlDrvEvent)(long)d->rfd;
        driver_select(d->port, event, ERL_DRV_READ|ERL_DRV_USE, 0);
        d->b.read_poll = 0;
    }
    return 0;
}

static void
enm_add_waiter(EnmData* d, erlang_ref* ref)
{
    EnmRecv *rcv, *cur;

    rcv = driver_alloc(sizeof(EnmRecv));
    if (rcv == 0)
        driver_failure(d->port, ENOMEM);
    memcpy(&rcv->ref, ref, sizeof *ref);
    rcv->rcvr = driver_caller(d->port);
    rcv->next = 0;
    driver_monitor_process(d->port, rcv->rcvr, &rcv->monitor);
    cur = d->waiting_recvs;
    if (cur == 0)
        d->waiting_recvs = rcv;
    else {
        while (cur) {
            if (cur->next != 0)
                cur = cur->next;
            else {
                cur->next = rcv;
                break;
            }
        }
    }
}

static int
enm_init()
{
    struct rlimit rl;

    if (getrlimit(RLIMIT_NOFILE, &rl) < 0)
        return -1;
    enm_sockets = (EnmData**)driver_alloc(rl.rlim_cur * sizeof(EnmData*));
    if (enm_sockets == 0)
        return -1;
    return 0;
}

static void
enm_finish()
{
    driver_free(enm_sockets);
}

static ErlDrvData
enm_start(ErlDrvPort port, char* command)
{
    EnmData* d = (EnmData*)driver_alloc(sizeof(EnmData));
    memset(d, 0, sizeof *d);
    d->port = port;
    d->waiting_recvs = 0;
    set_port_control_flags(port, PORT_CONTROL_FLAG_BINARY);
    return (ErlDrvData)d;
}

static void
enm_stop(ErlDrvData drv_data)
{
    EnmData* d = (EnmData*)drv_data;
    EnmRecv* rcv = d->waiting_recvs;
    ErlDrvTermData port = driver_mk_port(d->port);
    char refbuf[64];
    int index;

    enm_write_select(d, 0);
    enm_read_select(d, 0);
    while (rcv != 0) {
        EnmRecv* p = rcv;
        if (driver_demonitor_process(d->port, &rcv->monitor) == 0) {
            index = 0;
            ei_encode_version(refbuf, &index);
            ei_encode_ref(refbuf, &index, &rcv->ref);
            {
                ErlDrvTermData term[] = {
                    ERL_DRV_EXT2TERM, (ErlDrvTermData)refbuf, index+1,
                    ERL_DRV_ATOM, driver_mk_atom("error"),
                    ERL_DRV_ATOM, enm_errno_atom(ETERM),
                    ERL_DRV_TUPLE, 2,
                    ERL_DRV_TUPLE, 2,
                };
                erl_drv_send_term(port, rcv->rcvr, term,
                                  sizeof term/sizeof *term);
            }
        }
        rcv = rcv->next;
        driver_free(p);
    }
    if (d->fd != -1)
        nn_close(d->fd);
    d->fd = d->sfd = d->rfd = -1;
    driver_free(d);
}

static int
enm_do_send(EnmData* d, const struct nn_msghdr* msghdr)
{
    int rc, err;

    if (msghdr->msg_iovlen == 0)
        return 0;
    err = 0;
    do {
        rc = nn_sendmsg(d->fd, msghdr, NN_DONTWAIT);
        if (rc < 0) {
            err = errno;
            switch (err) {
            case EINTR:
            case EFSM:
                /* do nothing */
                break;
            case EAGAIN:
                d->b.writable = 0;
                break;
            default:
                enm_write_select(d, 0);
                enm_read_select(d, 0);
                driver_failure(d->port, err);
            }
        }
    } while (err == EINTR);
    return rc;
}

static void
enm_outputv(ErlDrvData drv_data, ErlIOVec *ev)
{
    EnmData* d = (EnmData*)drv_data;
    ErlIOVec qev;
    ErlDrvSizeT qtotal;
    struct nn_msghdr msghdr;
    int i, rc = -1, err;

    if (d->fd == -1 || d->protocol == NN_PULL || d->protocol == NN_SUB)
        return;
    qtotal = driver_peekqv(d->port, &qev);
    if (qtotal > 0) {
        memset(&msghdr, 0, sizeof msghdr);
        msghdr.msg_iov = (struct nn_iovec*)qev.iov;
        msghdr.msg_iovlen = qev.vsize;
        msghdr.msg_control = 0;
        err = 0;
        do {
            rc = enm_do_send(d, &msghdr);
            if (rc < 0) {
                err = errno;
                if (err == EAGAIN) {
                    d->b.writable = 0;
                    break;
                } else if (err != EINTR)
                    driver_failure(d->port, err);
            }
        } while (err == EINTR);
    }
    /*
     * Do nothing if the message has no data
     */
    if (ev->vsize == 0 ||
        (ev->vsize == 1 && *ev->binv == 0 && ev->iov->iov_len == 0))
        return;
    if (d->b.writable) {
        memset(&msghdr, 0, sizeof msghdr);
        msghdr.msg_iov = (struct nn_iovec*)ev->iov;
        msghdr.msg_iovlen = ev->vsize;
        msghdr.msg_control = 0;
        err = 0;
        do {
            rc = enm_do_send(d, &msghdr);
            if (rc < 0) {
                err = errno;
                if (err == EAGAIN) {
                    d->b.writable = 0;
                    break;
                } else if (err != EINTR)
                    driver_failure(d->port, err);
            }
        } while (err == EINTR);
    }
    if (rc < 0 && !d->b.writable) {
        rc = 0;
        d->b.busy = 1;
        set_busy_port(d->port, d->b.busy);
        for (i = 0; i < ev->vsize; i++) {
            ErlDrvBinary* bin = 0;
            if (ev->binv[i] != 0) {
                bin = ev->binv[i];
                driver_binary_inc_refc(bin);
            } else if (ev->iov[i].iov_len > 0) {
                SysIOVec* vec = &ev->iov[i];
                bin = driver_alloc_binary(vec->iov_len);
                memcpy(bin->orig_bytes, vec->iov_base, vec->iov_len);
            }
            if (bin != 0)
                driver_enq_bin(d->port, bin, 0, bin->orig_size);
        }
        if (!d->b.write_poll)
            enm_write_select(d, 1);
    }
    if (rc > 0 && d->protocol == NN_SURVEYOR && d->b.active != ENM_FALSE)
        enm_read_select(d, 1);
}

static ErlDrvSSizeT
enm_create_socket(EnmData* d, EnmArgs* args)
{
    ErlDrvSSizeT res;
    int rc, domain, err, opt;
    size_t optlen = sizeof d->sfd;

    d->fd = d->sfd = d->rfd = -1;
    d->b.active = ENM_TRUE;
    while (args->index < args->len) {
        opt = *args->buf++;
        args->index++;
        switch (opt) {
        case ENM_ACTIVE:
        case ENM_RAW:
        case ENM_BINARY:
        case ENM_DEADLINE:
        case ENM_SUBSCRIBE:
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
    domain = d->b.raw ? AF_SP_RAW : AF_SP;
    d->fd = nn_socket(domain, d->protocol);
    if (d->fd < 0)
        return enm_errno_tuple(*args->rbuf, errno);
    if (args->deadline != 0) {
        rc = nn_setsockopt(d->fd, NN_SURVEYOR, NN_SURVEYOR_DEADLINE,
                           &args->deadline, sizeof args->deadline);
        if (rc < 0) {
            err = errno;
            nn_close(d->fd);
            d->fd = -1;
            return enm_errno_tuple(*args->rbuf, err);
        }
    }
    if (args->resend_ivl != 0) {
        rc = nn_setsockopt(d->fd, NN_REQ, NN_REQ_RESEND_IVL,
                           &args->resend_ivl, sizeof args->resend_ivl);
        if (rc < 0) {
            err = errno;
            nn_close(d->fd);
            d->fd = -1;
            return enm_errno_tuple(*args->rbuf, err);
        }
    }
    if (args->b.topic_seen) {
        rc = nn_setsockopt(d->fd, NN_SUB, NN_SUB_SUBSCRIBE,
                           args->topic, strlen(args->topic));
        if (rc < 0) {
            err = errno;
            nn_close(d->fd);
            d->fd = -1;
            return enm_errno_tuple(*args->rbuf, err);
        }
    }
    if (d->protocol != NN_PULL && d->protocol != NN_SUB) {
        rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_SNDFD, &d->sfd, &optlen);
        if (rc < 0) {
            err = errno;
            nn_close(d->fd);
            d->fd = -1;
            return enm_errno_tuple(*args->rbuf, err);
        }
        enm_sockets[d->sfd] = d;
        d->b.writable = 1;
        if (args->sndbuf != 0) {
            rc = nn_setsockopt(d->fd, NN_SOL_SOCKET, NN_SNDBUF,
                               &args->sndbuf, sizeof args->sndbuf);
            if (rc < 0) {
                err = errno;
                nn_close(d->fd);
                d->fd = -1;
                d->sfd = -1;
                return enm_errno_tuple(*args->rbuf, err);
            }
        } else {
            optlen = sizeof args->sndbuf;
            rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_SNDBUF,
                               &args->sndbuf, &optlen);
            if (rc < 0) {
                err = errno;
                nn_close(d->fd);
                d->fd = -1;
                d->sfd = -1;
                return enm_errno_tuple(*args->rbuf, err);
            }
        }
        if (args->sndbuf != 0) {
            ErlDrvSizeT low = args->sndbuf >> 1, high = args->sndbuf;
            erl_drv_busy_msgq_limits(d->port, &low, &high);
        }
    }
    if (d->b.active) {
        if (d->protocol != NN_PUSH && d->protocol != NN_PUB) {
            rc = nn_getsockopt(d->fd, NN_SOL_SOCKET, NN_RCVFD, &d->rfd, &optlen);
            if (rc < 0) {
                err = errno;
                nn_close(d->fd);
                d->fd = -1;
                d->sfd = -1;
                return enm_errno_tuple(*args->rbuf, err);
            }
            enm_sockets[d->rfd] = d;
            if (d->protocol != NN_SURVEYOR)
                enm_read_select(d, 1);
        }
        if (args->rcvbuf != 0) {
            rc = nn_setsockopt(d->fd, NN_SOL_SOCKET, NN_RCVBUF,
                               &args->rcvbuf, sizeof args->rcvbuf);
            if (rc < 0) {
                err = errno;
                enm_read_select(d, 0);
                nn_close(d->fd);
                d->fd = -1;
                d->sfd = -1;
                return enm_errno_tuple(*args->rbuf, err);
            }
        }
    }
    return enm_ok(*args->rbuf);
}

static ErlDrvSSizeT
enm_control(ErlDrvData drv_data, unsigned int command,
            char* buf, ErlDrvSizeT len, char** rbuf, ErlDrvSizeT rlen)
{
    EnmData* d = (EnmData*)drv_data;
    ErlDrvSSizeT result;
    ErlDrvSizeT qsize;
    EnmRecv *cur, *prev;
    EnmArgs args;
    int rc, err, index, how, vsn;
    void* bf;
    char* outbuf;
    ei_x_buff xb;
    erlang_ref ref;
    ErlDrvBinary* bin;

    memset(&args, 0, sizeof args);
    args.buf = buf;
    args.len = len;
    args.rbuf = rbuf;
    args.rlen = rlen;

    switch (command) {
    case ENM_REQ:
    case ENM_REP:
    case ENM_BUS:
    case ENM_PUB:
    case ENM_SUB:
    case ENM_PUSH:
    case ENM_PULL:
    case ENM_SVYR:
    case ENM_RESP:
    case ENM_PAIR:
        d->protocol = enm_cmd_to_protocol(command);
        if (d->protocol < 0)
            return enm_errno_tuple(*rbuf, errno);
        return enm_create_socket(d, &args);
        break;

    case ENM_CONNECT:
    case ENM_BIND:
        if (d->fd == -1)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        rc = (command == ENM_CONNECT) ?
            nn_connect(d->fd, buf) :
            nn_bind(d->fd, buf);
        if (rc < 0) {
            err = errno;
            enm_write_select(d, 0);
            enm_read_select(d, 0);
            if (err == EBADF)
                return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
            else
                return enm_errno_tuple(*rbuf, err);
        }
        index = 0;
        ei_encode_version(*rbuf, &index);
        ei_encode_tuple_header(*rbuf, &index, 2);
        ei_encode_atom(*rbuf, &index, "ok");
        ei_encode_long(*rbuf, &index, rc);
        return index;
        break;

    case ENM_CLOSE:
        enm_write_select(d, 0);
        enm_read_select(d, 0);
        qsize = driver_sizeq(d->port);
        if (qsize > 0)
            driver_deq(d->port, qsize);
        result = 0;
        err = 0;
        if (d->fd != -1) {
            do {
                rc = nn_close(d->fd);
                if (rc < 0 ) {
                    err = errno;
                    if (err == EBADF)
                        result = (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
                }
            } while (err == EINTR);
        }
        d->fd = d->sfd = d->rfd = -1;
        if (result != 0) return result;
        break;

    case ENM_SHUTDOWN:
        if (d->fd == -1)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        how = GETINT32(buf);
        for (;;) {
            rc = nn_shutdown(d->fd, how);
            if (rc < 0) {
                err = errno;
                if (err != EINTR) {
                    enm_write_select(d, 0);
                    enm_read_select(d, 0);
                    if (err == EBADF)
                        return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
                    else
                        return enm_errno_tuple(*rbuf, err);
                }
            } else
                break;
        }
        break;

    case ENM_TERM:
        nn_term();
        break;

    case ENM_GETOPTS:
        return enm_getopts(d, &args);
        break;

    case ENM_SETOPTS:
        return enm_setopts(d, &args);
        break;

    case ENM_RECV:
        if (d->fd == -1 || d->protocol == NN_PUSH)
            return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
        index = 0;
        ei_decode_version(buf, &index, &vsn);
        ei_decode_ref(buf, &index, &ref);
        xb.index = 0;
        /*
         * If there are already waiting receivers, just add this recv to
         * the queue to preserve recv order.
         */
        if (d->waiting_recvs) {
            enm_add_waiter(d, &ref);
            ei_x_new_with_version(&xb);
            ei_x_encode_tuple_header(&xb, 2);
            ei_x_encode_ref(&xb, &ref);
            ei_x_encode_atom(&xb, "wait");
            enm_read_select(d, 1);
        }
        while (xb.index == 0) {
            rc = nn_recv(d->fd, &bf, NN_MSG, NN_DONTWAIT);
            if (rc < 0) {
                err = errno;
                if (err == EINTR)
                    continue;
                else if (err == EAGAIN) {
                    enm_add_waiter(d, &ref);
                    ei_x_new_with_version(&xb);
                    ei_x_encode_tuple_header(&xb, 2);
                    ei_x_encode_ref(&xb, &ref);
                    ei_x_encode_atom(&xb, "wait");
                    enm_read_select(d, 1);
                } else {
                    char errstr[64];
                    enm_write_select(d, 0);
                    enm_read_select(d, 0);
                    ei_x_new_with_version(&xb);
                    ei_x_encode_tuple_header(&xb, 2);
                    ei_x_encode_ref(&xb, &ref);
                    ei_x_encode_tuple_header(&xb, 2);
                    ei_x_encode_atom(&xb, "error");
                    enm_errno_str(err, errstr);
                    ei_x_encode_atom(&xb, errstr);
                }
            } else
                break;
        }
        bin = 0;
        if (xb.index == 0) {
            /*
             * We assume we need 40 bytes at the front of the encoded term
             * buffer for the version, tuple header, and ref. If that plus
             * the received data length is greater than rlen, it won't fit
             * into *rbuf, so we encode directly into a binary instead.
             */
            if (40+rc > rlen) {
                bin = driver_alloc_binary(40+rc);
                *rbuf = (char*)bin;
                outbuf = bin->orig_bytes;
            } else
                outbuf = *rbuf;
            index = 0;
            ei_encode_version(outbuf, &index);
            ei_encode_tuple_header(outbuf, &index, 2);
            ei_encode_ref(outbuf, &index, &ref);
            if (d->b.listmode)
                ei_encode_string_len(outbuf, &index, bf, rc);
            else
                ei_encode_binary(outbuf, &index, bf, rc);
            nn_freemsg(bf);
            if (*rbuf == (char*)bin)
                bin->orig_size = index;
            rlen = index;
        } else {
            if (xb.index <= rlen)
                outbuf = *rbuf;
            else {
                bin = driver_alloc_binary(xb.index);
                *rbuf = (char*)bin;
                outbuf = bin->orig_bytes;
            }
            memcpy(outbuf, xb.buff, xb.index);
            ei_x_free(&xb);
            rlen = xb.index;
        }
        return rlen;
        break;

    case ENM_CANCEL_RECV:
        index = 0;
        ei_decode_version(buf, &index, &vsn);
        ei_decode_ref(buf, &index, &ref);
        cur = d->waiting_recvs;
        prev = 0;
        while (cur) {
            if (ENM_REFS_EQUAL(cur->ref, ref)) {
                if (prev != 0)
                    prev->next = cur->next;
                else
                    d->waiting_recvs = cur->next;
                driver_demonitor_process(d->port, &cur->monitor);
                driver_free(cur);
                break;
            }
            prev = cur;
            cur = cur->next;
        }
        if (!d->b.active)
            enm_read_select(d, 0);
        break;

    default:
        return (ErlDrvSSizeT)ERL_DRV_ERROR_BADARG;
    }
    return enm_ok(*rbuf);
}

static void
enm_ready_input(ErlDrvData drv_data, ErlDrvEvent event)
{
    EnmData* d = enm_sockets[(long)event];
    ErlDrvTermData port = driver_mk_port(d->port);
    void* buf;
    char pktname[64];
    int rc, err;

    rc = nn_recv(d->fd, &buf, NN_MSG, NN_DONTWAIT);
    if (rc < 0) {
        err = errno;
        if (err == EAGAIN)
            return;
        strcpy(pktname, enm_protocol_name(d->protocol));
        if (d->protocol == NN_SURVEYOR && err == EFSM) {
            /*
             * TODO: nanomsg documentation for nn_survey says that when the
             * surveyor deadline expires, recv returns ETIMEDOUT, but that
             * doesn't seem to be the case. Instead, we seem to get
             * EFSM. The nanomsg 0.4-beta survey.c test file also checks
             * for EFSM when the deadline hits. Unclear whether the doc or
             * the code is correct.
             */
            strcat(pktname, "_deadline");
            {
                ErlDrvTermData term[] = {
                    ERL_DRV_ATOM, driver_mk_atom(pktname),
                    ERL_DRV_PORT, port,
                    ERL_DRV_TUPLE, 2,
                };
                erl_drv_output_term(port, term, sizeof term/sizeof *term);
            }
            d->b.active = ENM_FALSE;
            enm_read_select(d, 0);
        } else {
            strcat(pktname, "_error");
            {
                ErlDrvTermData term[] = {
                    ERL_DRV_ATOM, driver_mk_atom(pktname),
                    ERL_DRV_PORT, port,
                    ERL_DRV_ATOM, enm_errno_atom(err),
                    ERL_DRV_TUPLE, 3,
                };
                erl_drv_output_term(port, term, sizeof term/sizeof *term);
            }
        }
        if (err == ETERM) {
            enm_read_select(d, 0);
            enm_write_select(d, 0);
            nn_close(d->fd);
            d->fd = -1;
        }
    } else {
        if (d->waiting_recvs != 0) {
            EnmRecv* rcv = d->waiting_recvs;
            int index = 0;
            char refbuf[64];
            ei_encode_version(refbuf, &index);
            ei_encode_ref(refbuf, &index, &rcv->ref);
            {
                ErlDrvTermData t[] = {
                    ERL_DRV_EXT2TERM, (ErlDrvTermData)refbuf, index+1,
                    d->b.listmode ? ERL_DRV_STRING : ERL_DRV_BUF2BINARY,
                    (ErlDrvTermData)buf, rc,
                    ERL_DRV_TUPLE, 2,
                };
                erl_drv_send_term(port, rcv->rcvr, t, sizeof t/sizeof *t);
            }
            driver_demonitor_process(d->port, &rcv->monitor);
            d->waiting_recvs = rcv->next;
            driver_free(rcv);
            if (!d->b.active && d->waiting_recvs == 0)
                enm_read_select(d, 0);
        } else {
            ErlDrvTermData term[] = {
                ERL_DRV_ATOM, enm_protocol_atom(d->protocol),
                ERL_DRV_PORT, port,
                d->b.listmode ? ERL_DRV_STRING : ERL_DRV_BUF2BINARY,
                (ErlDrvTermData)buf, rc,
                ERL_DRV_TUPLE, 3,
            };
            erl_drv_output_term(port, term, sizeof term/sizeof *term);
            if (d->b.active == ENM_N && --d->n_count == 0) {
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
                d->b.active = ENM_FALSE;
                enm_read_select(d, 0);
            } else if (d->b.active == ENM_ONCE) {
                d->b.active = ENM_FALSE;
                enm_read_select(d, 0);
            }
        }
        nn_freemsg(buf);
    }
}

static void
enm_ready_output(ErlDrvData drv_data, ErlDrvEvent event)
{
    EnmData* d = enm_sockets[(long)event];
    struct nn_msghdr msghdr;
    ErlIOVec ev;
    ErlDrvSizeT total;
    int rc;

    d->b.writable = 1;
    total = driver_peekqv(d->port, &ev);
    if (total == 0)
        return;
    memset(&msghdr, 0, sizeof msghdr);
    msghdr.msg_iov = (struct nn_iovec*)ev.iov;
    msghdr.msg_iovlen = ev.vsize;
    msghdr.msg_control = 0;
    rc = enm_do_send(d, &msghdr);
    if (rc > 0)
        driver_deq(d->port, rc);
    if (rc == total && d->b.writable) {
        if (d->b.busy) {
            d->b.busy = 0;
            set_busy_port(d->port, d->b.busy);
        }
        enm_write_select(d, 0);
    }
}

static void
enm_process_exit(ErlDrvData drv_data, ErlDrvMonitor* monitor)
{
    EnmData* d = (EnmData*)drv_data;
    EnmRecv* cur = d->waiting_recvs;
    EnmRecv* prev = 0;

    while (cur) {
        if (driver_compare_monitors(monitor, &cur->monitor) == 0) {
            if (prev != 0)
                prev->next = cur->next;
            else
                d->waiting_recvs = cur->next;
            driver_free(cur);
            break;
        }
        prev = cur;
        cur = cur->next;
    }
}

static void
enm_stop_select(ErlDrvEvent event, void* arg)
{
    /* do nothing */
}

static ErlDrvEntry drv_entry = {
    enm_init,
    enm_start,
    enm_stop,
    0,
    enm_ready_input,
    enm_ready_output,
    "enm_drv",
    enm_finish,
    0,
    enm_control,
    0,
    enm_outputv,
    0,
    0,
    0,
    0,
    ERL_DRV_EXTENDED_MARKER,
    ERL_DRV_EXTENDED_MAJOR_VERSION,
    ERL_DRV_EXTENDED_MINOR_VERSION,
    ERL_DRV_FLAG_USE_PORT_LOCKING,
    0,
    enm_process_exit,
    enm_stop_select,
};

DRIVER_INIT(enm_drv)
{
    return &drv_entry;
}
