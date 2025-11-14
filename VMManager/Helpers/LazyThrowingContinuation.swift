nonisolated
struct LazyThrowingContinuation<Value, Failure> where Failure: Error {
    private let continuation: AsyncThrowingStream<Value, Error>.Continuation
    
    init(continuation: AsyncThrowingStream<Value, Error>.Continuation) {
        self.continuation = continuation
    }
    
    func finish(throwing error: Failure? = nil) {
        continuation.finish(throwing: error)
    }
    
    func yield(_ value: Value) {
        continuation.yield(value)
    }
    
    func yield(with result: Result<Value, Failure>) {
        continuation.yield(with:
            Result<Value, Error> {
                try result.get()
            }
        )
    }
}

func withLazyThrowingContinuation<Value, Failure>(continuation: AsyncThrowingStream<Value, Error>.Continuation, failure: Failure.Type, _ callback: @escaping @Sendable (LazyThrowingContinuation<Value, Failure>) -> Void) where Failure: Error {
    callback(LazyThrowingContinuation(continuation: continuation))
}


extension AsyncThrowingStream where Failure == Error {
    init<ActualFailure>(failure: ActualFailure.Type, bufferingPolicy: Continuation.BufferingPolicy = .unbounded, _ callback: @escaping @Sendable (LazyThrowingContinuation<Element, ActualFailure>) -> Void) where ActualFailure: Error {
        self.init(bufferingPolicy: bufferingPolicy) { withLazyThrowingContinuation(continuation: $0, failure: failure, callback) }
    }
}
