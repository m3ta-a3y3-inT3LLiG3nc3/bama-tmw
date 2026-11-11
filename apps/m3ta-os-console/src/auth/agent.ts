import { AbstractAgent, type BaseEvent, type RunAgentInput } from "@ag-ui/client";
import { Observable } from "rxjs";
import { getAuthRegistry, openDispatchTicket } from "./registry.ts";

/**
 * One agent instance per request. Upstream work starts only after the
 * dispatch barrier, and only if logout has not already aborted the ticket.
 */
export class ConsoleAgent extends AbstractAgent {
  readonly userId: string;
  readonly permitId: string;

  constructor(userId: string, permitId = "") {
    super({ agentId: "default", description: "M3ta-OS Console" });
    this.userId = userId;
    this.permitId = permitId;
  }

  override clone(): ConsoleAgent {
    const copy = new ConsoleAgent(this.userId, this.permitId);
    copy.threadId = this.threadId;
    copy.messages = [...this.messages];
    copy.state = this.state;
    return copy;
  }

  run(input: RunAgentInput): Observable<BaseEvent> {
    return new Observable((subscriber) => {
      const ticket = openDispatchTicket(this.userId, input);
      let closed = false;
      const finish = () => {
        if (closed) return;
        closed = true;
        subscriber.complete();
      };
      const emit = (event: BaseEvent) => {
        if (closed || ticket.signal.aborted) return;
        subscriber.next(event);
      };
      void (async () => {
        try {
          await getAuthRegistry().dispatchBarrier;
          if (ticket.signal.aborted) {
            ticket.phase = "cancelled";
            return;
          }
          ticket.phase = "dispatched";
          await getAuthRegistry().agentWork(input, ticket.signal, emit);
          if (ticket.phase === "dispatched") ticket.phase = "finished";
        } catch (error) {
          if (!closed && !ticket.signal.aborted) subscriber.error(error);
        } finally {
          finish();
        }
      })();
      return () => {
        finish();
      };
    });
  }
}
