# Informer Configuration

Reconcilers and Watchers receive events from an Informer, and both together are managed by an informer controller.
The configuration of this controller created by `simple.App` is done in `simple.AppConfig.InformerConfig`.

## InformerConfig

`simple.AppConfig.InformerConfig` is of type `simple.AppInformerConfig`, which is defined as:
```go
// AppInformerConfig contains configuration for the App's internal operator.InformerController
type AppInformerConfig struct {
	// InformerOptions are the options for the informer.
	InformerOptions operator.InformerOptions
	// RetryPolicy is the policy for retrying events.
	RetryPolicy operator.RetryPolicy
	// RetryDequeuePolicy is the policy for dequeuing events.
	RetryDequeuePolicy operator.RetryDequeuePolicy
	// FinalizerSupplier is used to generate the finalizer for the kind.
	FinalizerSupplier operator.FinalizerSupplier
	// InProgressFinalizerSupplier is used to generate the "in-progress" finalizer used by opinionated adds,
	// before the "normal" finalizer (provided by FinalizerSupplier) is applied when the add completes successfully.
	// By default, this is "<app name>-wip"
	InProgressFinalizerSupplier operator.FinalizerSupplier
	// InformerSupplier can be set to specify a function for creating informers for kinds.
	// If left unset, DefaultInformerSupplier will be used.
	InformerSupplier InformerSupplier
}
```
`operator.InformerOptions` is defined as
```go
// InformerOptions are generic options for all Informer implementations.
type InformerOptions struct {
	// ListWatchOptions are the options for filtering the watch based on namespace and other compatible filters.
	ListWatchOptions ListWatchOptions
	// CacheResyncInterval is the interval at which the informer will emit CacheResync events for all resources in the cache.
	// This is distinct from a full resync, as no information is fetched from the API server.
	// Changes to this value after run() is called will not take effect.
	// An empty value will disable cache resyncs.
	CacheResyncInterval time.Duration
	// EventTimeout is the timeout for an event to be processed.
	// If an event is not processed within this timeout, it will be dropped.
	// The timeout cannot be larger than the cache resync interval, if it is,
	// the cache resync interval will be used instead.
	// An empty value will disable event timeouts.
	EventTimeout time.Duration
	// ErrorHandler is called if the informer encounters an error which does not stop the informer from running,
	// but may stop it from processing a given event.
	ErrorHandler func(context.Context, error)
	// HealthCheckIgnoreSync will set the KubernetesBasedInformer HealthCheck to return ok once the informer is started,
	// rather than waiting for the informer to finish with its initial list sync.
	// You may want to set this to `true` if you have a particularly long initial sync period and don't want readiness checks failing.
	HealthCheckIgnoreSync bool
	// UseWatchList if turned on instructs the reflector to open a stream to bring data from the API server.
	// Streaming has the primary advantage of using fewer server's resources to fetch data.
	//
	// The old behavior establishes a LIST request which gets data in chunks.
	// Paginated list is less efficient and depending on the actual size of objects
	// might result in an increased memory consumption of the APIServer.
	//
	// Defaults to false. Requires Kubernetes 1.27+ when enabled.
	// See https://github.com/kubernetes/enhancements/tree/master/keps/sig-api-machinery/3157-watch-list#design-details
	UseWatchList bool
	// WatchListPageSize is the requested chunk size for paginated LIST operations.
	// This significantly reduces memory usage when watching large numbers of objects (>10K).
	// Recommended values: 5000-10000 for most use cases.
	// Note: This only affects traditional LIST operations. It does NOT apply to watch-list streaming (UseWatchList).
	// An empty value (0) will use client-go's default pagination behavior based on resource version.
	WatchListPageSize int64
	// MaxConcurrentWorkers is the maximum number of concurrent workers for event processing in ConcurrentInformer.
	// Each worker maintains a queue of events which are processed sequentially.
	// Events for a particular object are assigned to the same worker to maintain in-order delivery per object.
	// An empty value (0) will use the default of 10 workers.
	MaxConcurrentWorkers uint64
}
```

## Error Handling

If `AppInformerConfig.InformerOptions.ErrorHandler` is defined, it will be called prior to requeuing an error returned from a watcher or reconciler. By default, this is a function which logs the error to the logger from the context.

## Retries and Dequeuing

`simple.App` internally manages retries and dequeueing of reconcile events. If a watcher or reconciler call returns an error, it is automatically retried based on the `RetryPolicy`. When a new event for the same resource arrives while a retry is still in the queue, the retry may be dequeued per the `RetryDequeuePolicy`.

`RetryPolicy` is defined as
```go
// RetryPolicy is a function that defines whether an event should be retried, based on the error and number of attempts.
// It returns a boolean indicating whether another attempt should be made, and a time.Duration after which that attempt should be made again.
type RetryPolicy func(err error, attempt int) (bool, time.Duration)
```
If unspecified, `AppInformerConfig.RetryPolicy` defaults to an exponential backoff retry policy (`operator.DefaultRetryPolicy`) that retries a total of five times before giving up. 

`operator.ExponentialBackoffRetryPolicy(initialDelay time.Duration, maxAttempts int)` can be used to create an arbitrary exponential backoff retry policy.

Custom retry policies may want to interrogate the supplied error to determine if a retry should be performed.

Dequeuing existing retries is managed with `AppInformerConfig.RetryDequeuePolicy`. A `RetryDequeuePolicy` is a function defined as:
```go
// RetryDequeuePolicy is a function that defines when a retry should be dequeued when a new action is taken on a resource.
// It accepts information about the new action being taken, and information about the current queued retry,
// and returns `true` if the retry should be dequeued.
// A RetryDequeuePolicy may be called multiple times for the same action, depending on the number of pending retries for the object.
type RetryDequeuePolicy func(newAction ResourceAction, newObject resource.Object, retryAction ResourceAction, retryObject resource.Object, retryError error) bool
```
If unspecified, it uses the default (`operator.OpinionatedRetryDequeuePolicy`) that is defined as
```go
// OpinionatedRetryDequeuePolicy is a RetryDequeuePolicy which has the following logic:
// 1. If the newAction is a delete, dequeue the retry
// 2. If the newAction and retryAction are different, keep the retry (for example, a queued create retry, and a received update action)
// 3. If the generation of newObject and retryObject is the same, keep the retry
// 4. Otherwise, dequeue the retry
var OpinionatedRetryDequeuePolicy = func(newAction ResourceAction, newObject resource.Object, retryAction ResourceAction, retryObject resource.Object, _ error) bool {
	if newAction == ResourceActionDelete {
		return true
	}
	if newAction != retryAction {
		return false
	}
	if newObject.GetGeneration() == retryObject.GetGeneration() {
		return false
	}
	return true
}
```

## Finalizer Suppliers

Both the `OpinionatedReconciler` and `OpinionatedWatcher` manage finalizers, and the names of the finalizers are supplied by `AppInformerConfig.FinalizerSupplier` and `AppInformerConfig.InProgressFinalizerSupplier`.

An `operator.FinalizerSupplier` is defined as
```go
// FinalizerSupplier represents a function that creates string finalizer from provider schema.
type FinalizerSupplier func(sch resource.Schema) string
```
By default, `operator.DefaultFinalizerSupplier` and `operator.InProgressFinalizerSupplier` are used, defined as:
```go
// DefaultFinalizerSupplier crates finalizer following to pattern `operator.{version}.{kind}.{group}`.
func DefaultFinalizerSupplier(sch resource.Schema) string {
	return fmt.Sprintf("operator.%s.%s.%s", sch.Version(), sch.Kind(), sch.Group())
}

func InProgressFinalizerSupplier(sch resource.Schema) string {
	return fmt.Sprintf("wip.%s.%s.%s", sch.Version(), sch.Kind(), sch.Group())
}
```
The in-progress finalizer is added upon event ingestion by an `OpinionatedReconciler` or `OpinionatedWatcher` if no finalizer is present, and is replaced by the normal finalizer when the downstream request succeeds.

## InformerSupplier

`InformerSupplier` is defined as
```go
// InformerSupplier is a function which creates an operator.Informer for a kind, given a ClientGenerator and ListWatchOptions
type InformerSupplier func(
	kind resource.Kind, clients resource.ClientGenerator, options operator.InformerOptions,
) (operator.Informer, error)
```
and uses the following default if not overridden:
```go
// DefaultInformerSupplier is a default InformerSupplier function which creates a basic operator.KubernetesBasedInformer.
// Note: This supplier does NOT respect WatchListPageSize or UseWatchList configuration.
// For memory-optimized informers that support these options, use OptimizedInformerSupplier instead.
var DefaultInformerSupplier = func(
	kind resource.Kind, clients resource.ClientGenerator, options operator.InformerOptions,
) (operator.Informer, error) {
	client, err := clients.ClientFor(kind)
	if err != nil {
		return nil, err
	}

	inf, err := operator.NewKubernetesBasedInformer(kind, client, options)
	if err != nil {
		return nil, err
	}

	return operator.NewConcurrentInformerFromOptions(inf, options)
}
```
It is used when `simple.App` creates a new `Informer` for a kind if a watcher or reconciler are configured for it. This allows the user to swap in different `Informer` implementations if they wish. The `operator` package has an alternate informer that can use a custom (and therefore not in-memory like the `KubernetesBasedInformer`) cache, using `NewCustomCacheInformer`, and an implementation of this using memcached as the storage with `NewMemcachedInformer`.

By default, the `KubernetesBasedInformer`, which uses kubernetes' `cache.NewSharedIndexInformer` under the hood, is wrapped in `operator.NewConcurrentInformerFromOptions`, which allows for concurrent event processing (as opposed to the standard kubernetes informer logic, where all events are placed in a queue and processed one by one). This concurrency guarantees that events for the same resource will be processed in sequence by the same goroutine, but otherwise will spread informer events across a configured number of goroutines to allow for faster processing of events, particularly at startup, when all resources currently in the APIServer must be processed before the informer will begin processing new events.

### OptimizedInformerSupplier

`simple.OptimizedInformerSupplier` is an alternative to `DefaultInformerSupplier` that fully respects the `WatchListPageSize` and `UseWatchList` options in `InformerOptions`. The default supplier ignores these settings. Use it when watching large numbers of objects (>10K) or in memory-constrained environments:

```go
simple.AppConfig{
    InformerConfig: simple.AppInformerConfig{
        InformerSupplier: simple.OptimizedInformerSupplier,
        InformerOptions: operator.InformerOptions{
            UseWatchList:      true,  // streaming, requires Kubernetes 1.27+
            WatchListPageSize: 5000,  // chunk size for paginated LIST fallback
        },
    },
    // ...
}
```

`OptimizedInformerSupplier` is marked experimental and may change in future releases.

## Health Checks

By default, the health check returned by an `Informer` will not return healthy until all start-up events have been processed. While the `ConcurrentInformer` makes this faster, there may be scenarios where this start-up time is still too lengthy and having the pod be unhealthy for that start-up duration will cause it to be killed. In that case, `AppInformerConfig.InformerOptions.HealthCheckIgnoreSync` can be set to `true` to have the health check return healthy so long as the informer is running.