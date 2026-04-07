# Reconciler Patterns

## Finalizers

Use finalizers to ensure cleanup of external resources before a Kubernetes resource is deleted. Without a finalizer, the resource may be deleted before the reconciler has a chance to clean up. Finalizers are automatically managed by the `OpinionatedReconciler` and `OpinionatedWatcher`, but can be manually managed if preferred:

```go
const myKindFinalizer = "my-app.grafana.app/finalizer"

func (r *MyKindReconciler) reconcile(
    ctx context.Context,
    req operator.TypedReconcileRequest[*v1.MyKind],
) (operator.ReconcileResult, error) {
    obj := req.Object

    // Handle deletion
    if obj.DeletionTimestamp != nil {
        if containsString(obj.Finalizers, myKindFinalizer) {
            // Run cleanup
            if err := r.cleanupExternalResources(ctx, obj); err != nil {
                return operator.ReconcileResult{}, fmt.Errorf("cleanup: %w", err)
            }
            // Remove finalizer
            obj.Finalizers = removeString(obj.Finalizers, myKindFinalizer)
            if _, err := r.client.Update(ctx, obj, resource.UpdateOptions{}); err != nil {
                return operator.ReconcileResult{}, fmt.Errorf("removing finalizer: %w", err)
            }
        }
        return operator.ReconcileResult{}, nil
    }

    // Add finalizer on first reconcile
    if !containsString(obj.Finalizers, myKindFinalizer) {
        obj.Finalizers = append(obj.Finalizers, myKindFinalizer)
        if _, err := r.client.Update(ctx, obj, resource.UpdateOptions{}); err != nil {
            return operator.ReconcileResult{}, fmt.Errorf("adding finalizer: %w", err)
        }
        // Return early — the update will trigger another reconcile
        return operator.ReconcileResult{}, nil
    }

    // ... normal reconcile logic ...
}

func containsString(slice []string, s string) bool {
    for _, item := range slice {
        if item == s { return true }
    }
    return false
}

func removeString(slice []string, s string) []string {
    result := make([]string, 0, len(slice))
    for _, item := range slice {
        if item != s { result = append(result, item) }
    }
    return result
}
```

When managing finalizers manually, be sure to set `UsePlain: true` for the ManagedKind's `ReconcileOptions`.

## Polling External Systems with RequeueAfter

When an external operation is asynchronous, poll until it completes:

```go
func (r *MyKindReconciler) reconcile(
    ctx context.Context,
    req operator.TypedReconcileRequest[*v1.MyKind],
) (operator.ReconcileResult, error) {
    obj := req.Object

    switch obj.Status.State {
    case "", "Pending":
        // Kick off the async operation
        jobID, err := r.externalClient.StartJob(ctx, buildJobSpec(obj))
        if err != nil {
            return operator.ReconcileResult{}, fmt.Errorf("starting job: %w", err)
        }
        _, err = resource.UpdateObject(ctx, r.client, obj.GetStaticMetadata().Identifier(),
            func(o *v1.MyKind, _ bool) (*v1.MyKind, error) {
                o.Status.State = "Provisioning"
                o.Status.ExternalJobID = jobID
                return o, nil
            },
            resource.UpdateOptions{Subresource: "status"},
        )
        if err != nil {
            return operator.ReconcileResult{}, err
        }
        // Check back in 10 seconds
        return operator.ReconcileResult{RequeueAfter: 10 * time.Second}, nil

    case "Provisioning":
        status, err := r.externalClient.GetJobStatus(ctx, obj.Status.ExternalJobID)
        if err != nil {
            return operator.ReconcileResult{}, fmt.Errorf("checking job status: %w", err)
        }
        var newState, newMessage string
        switch status {
        case "running":
            return operator.ReconcileResult{RequeueAfter: 10 * time.Second}, nil
        case "done":
            newState = "Ready"
        case "failed":
            newState = "Error"
            newMessage = "External job failed"
        default:
            return operator.ReconcileResult{}, fmt.Errorf("unknown provisioning status '%s'", status)
        }
        _, err = resource.UpdateObject(ctx, r.client, obj.GetStaticMetadata().Identifier(),
            func(o *v1.MyKind, _ bool) (*v1.MyKind, error) {
                o.Status.State = newState
                o.Status.Message = newMessage
                return o, nil
            },
            resource.UpdateOptions{Subresource: "status"},
        )
        return operator.ReconcileResult{}, err

    case "Ready":
        // Ensure still in sync
        return r.reconcileReady(ctx, obj)
    }

    return operator.ReconcileResult{}, nil
}
```

## Atomic Status Updates with resource.UpdateObject

Use `resource.UpdateObject` to update status — it fetches the latest version of the object, applies your update function, then pushes the result. This avoids `409 Conflict` errors that occur when a reconcile event races with a user spec change:

```go
_, err := resource.UpdateObject(ctx, r.client, req.Object.GetStaticMetadata().Identifier(),
    func(obj *v1alpha1.MyKind, exists bool) (*v1alpha1.MyKind, error) {
        obj.Status.LastObservedGeneration = req.Object.GetGeneration()
        obj.Status.State = "Ready"
        obj.Status.Message = ""
        return obj, nil
    },
    resource.UpdateOptions{Subresource: "status"},
)
```

Never use `client.Update` for status — it sends the full object body and conflicts with concurrent spec writes.

## Generation-Based Status Staleness

Set `LastObservedGeneration` after successfully reconciling a generation. Consumers can check `status.lastObservedGeneration == metadata.generation` to know if the status is current:

```go
obj.Status.LastObservedGeneration = obj.GetGeneration()
```

Skip reconciliation entirely if already processed. Note this also skips `ReconcileActionResynced` events for unchanged resources — this is intentional when you only want to react to spec changes:

```go
if obj.GetGeneration() == obj.Status.LastObservedGeneration {
    return operator.ReconcileResult{}, nil
}
```

## Structured Logging

```go
func (r *MyKindReconciler) reconcile(
    ctx context.Context,
    req operator.TypedReconcileRequest[*v1.MyKind],
) (operator.ReconcileResult, error) {
    log := logging.FromContext(ctx).With(
        "name", req.Object.GetName(),
        "namespace", req.Object.GetNamespace(),
        "generation", req.Object.GetGeneration(),
    )

    log.Info("Starting reconcile")

    if err := r.doWork(ctx, req.Object); err != nil {
        log.Error("Reconcile failed", "error", err)
        return operator.ReconcileResult{}, err
    }

    log.Info("Reconcile complete")
    return operator.ReconcileResult{}, nil
}
```

## Permanent vs Transient Errors

```go
// Mark permanent errors in status and stop retrying
type PermanentError struct{ msg string }
func (e PermanentError) Error() string { return e.msg }

func (r *MyKindReconciler) reconcile(
    ctx context.Context,
    req operator.TypedReconcileRequest[*v1.MyKind],
) (operator.ReconcileResult, error) {
    obj := req.Object
    if err := r.doWork(ctx, obj); err != nil {
        var permErr PermanentError
        if errors.As(err, &permErr) {
            // Update status and don't retry
            msg := permErr.Error()
            _, _ = resource.UpdateObject(ctx, r.client, obj.GetStaticMetadata().Identifier(),
                func(o *v1.MyKind, _ bool) (*v1.MyKind, error) {
                    o.Status.State = "Error"
                    o.Status.Message = msg
                    return o, nil
                },
                resource.UpdateOptions{Subresource: "status"},
            )
            return operator.ReconcileResult{}, nil // nil error = no retry
        }
        // Transient error — SDK will retry with backoff
        return operator.ReconcileResult{}, fmt.Errorf("transient error: %w", err)
    }
    return operator.ReconcileResult{}, nil
}
```

## Testing Reconcilers

The SDK does not ship fake client implementations. Implement the `resource.Client` interface in your test package as needed. A minimal stub only needs to implement the methods your reconciler actually calls:

```go
type fakeClient struct {
    objects map[string]*v1.MyKind
    updated *v1.MyKind
}

func (f *fakeClient) Get(ctx context.Context, id resource.Identifier) (resource.Object, error) {
    obj, ok := f.objects[id.Name]
    if !ok {
        return nil, fmt.Errorf("not found")
    }
    return obj, nil
}

func (f *fakeClient) Update(ctx context.Context, id resource.Identifier, obj resource.Object, opts resource.UpdateOptions) (resource.Object, error) {
    typed := obj.(*v1.MyKind)
    f.updated = typed
    f.objects[id.Name] = typed
    return typed, nil
}

// Implement remaining resource.Client methods as no-ops or panics.

func TestMyKindReconciler_Reconcile(t *testing.T) {
    obj := &v1.MyKind{
        ObjectMeta: metav1.ObjectMeta{
            Name:      "test",
            Namespace: "default",
        },
        Spec: v1.MyKindSpec{Title: "Test"},
    }

    client := &fakeClient{objects: map[string]*v1.MyKind{"test": obj}}
    fakeExternal := &fakeExternalClient{}

    r := NewMyKindReconciler(client)
    r.externalClient = fakeExternal

    result, err := r.reconcile(context.Background(), operator.TypedReconcileRequest[*v1.MyKind]{
        Object: obj,
        Action: operator.ReconcileActionCreated,
    })

    assert.NoError(t, err)
    assert.Equal(t, operator.ReconcileResult{}, result)
    assert.Equal(t, "Ready", client.updated.Status.State)
}
```

## Context Usage

Always propagate context from `Reconcile` to all downstream calls. Never create a new background context:

```go
// Good
result, err := r.externalClient.DoWork(ctx, params)

// Bad — loses deadline, cancellation, and trace context
result, err := r.externalClient.DoWork(context.Background(), params)
```
