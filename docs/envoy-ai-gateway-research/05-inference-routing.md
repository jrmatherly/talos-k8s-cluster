# Envoy AI Gateway Inference Routing Research

> Sources:
> - https://aigateway.envoyproxy.io/docs/capabilities/inference/
> - https://aigateway.envoyproxy.io/docs/capabilities/inference/httproute-inferencepool
> - https://aigateway.envoyproxy.io/docs/capabilities/inference/aigatewayroute-inferencepool
> Reviewed: December 2025

## Overview

The Envoy AI Gateway provides intelligent inference routing through InferencePool integration, enabling:
- Dynamic load balancing across inference endpoints
- Real-time metrics-based routing
- Support for self-hosted models (vLLM, etc.)
- Integration with Gateway API standards

## InferencePool Purpose

InferencePool enables "Intelligent Endpoint Selection" - automatically routing requests to optimal inference endpoints based on:
- Real-time metrics (KV-cache, queue depth)
- Endpoint availability
- Custom scheduling logic via Endpoint Picker Provider (EPP)

## Two Routing Approaches

### 1. HTTPRoute + InferencePool (Standard Gateway API)

Uses Kubernetes Gateway API's HTTPRoute with InferencePool backend references.

**Best for**: Simple path-based routing, standard Kubernetes deployments

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: inference-pool-with-httproute
  namespace: default
spec:
  parentRefs:
    - group: gateway.networking.k8s.io
      kind: Gateway
      name: inference-pool-with-httproute
      namespace: default
  rules:
    - backendRefs:
        - group: inference.networking.k8s.io
          kind: InferencePool
          name: vllm-llama3-8b-instruct
          namespace: default
          port: 8080
          weight: 1
      matches:
        - path:
            type: PathPrefix
            value: /
      timeouts:
        request: 60s
```

**Gateway Configuration**:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: inference-pool-with-httproute
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-pool-with-httproute
  namespace: default
spec:
  gatewayClassName: inference-pool-with-httproute
  listeners:
    - name: http
      protocol: HTTP
      port: 80
```

### 2. AIGatewayRoute + InferencePool (AI-Aware Routing)

Uses AI Gateway's custom AIGatewayRoute for AI-specific features.

**Best for**: Model-based routing, multi-model deployments, OpenAI API compatibility

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIGatewayRoute
metadata:
  name: inference-pool-with-aigwroute
  namespace: default
spec:
  parentRefs:
    - name: inference-pool-with-aigwroute
      kind: Gateway
      group: gateway.networking.k8s.io
  rules:
    - matches:
        - headers:
            - type: Exact
              name: x-ai-eg-model
              value: meta-llama/Llama-3.1-8B-Instruct
      backendRefs:
        - group: inference.networking.k8s.io
          kind: InferencePool
          name: vllm-llama3-8b-instruct
```

## Key Differences

| Feature | HTTPRoute | AIGatewayRoute |
|---------|-----------|----------------|
| API Standard | Gateway API v1 | AI Gateway custom |
| Model Extraction | Manual | Automatic from request body |
| OpenAI Validation | No | Built-in |
| Multi-model Routing | Path-based | Header/model-based |
| AI Metrics | No | Token tracking, model metrics |

## Mixed Backend Strategy

AIGatewayRoute supports combining InferencePool and AIServiceBackend:

```yaml
apiVersion: aigateway.envoyproxy.io/v1alpha1
kind: AIGatewayRoute
metadata:
  name: mixed-backends
spec:
  parentRefs:
    - name: ai-gateway
      kind: Gateway
      group: gateway.networking.k8s.io
  rules:
    # Self-hosted model via InferencePool
    - matches:
        - headers:
            - name: x-ai-eg-model
              value: mistral:latest
      backendRefs:
        - group: inference.networking.k8s.io
          kind: InferencePool
          name: mistral-pool
    # External provider via AIServiceBackend
    - matches:
        - headers:
            - name: x-ai-eg-model
              value: gpt-4
      backendRefs:
        - name: openai-backend
```

## InferencePool Annotations

### Processing Body Mode
```yaml
metadata:
  annotations:
    aigateway.envoyproxy.io/processing-body-mode: "buffered"  # or "duplex"
```

### Mode Override Permission
```yaml
metadata:
  annotations:
    aigateway.envoyproxy.io/allow-mode-override: "true"
```

## Backend Reference Structure

```yaml
backendRefs:
  - group: inference.networking.k8s.io
    kind: InferencePool
    name: <pool-name>
    namespace: <namespace>
    port: 8080
    weight: 1
```

## Requirements

### Prerequisites
- Kubernetes cluster with Gateway API support
- Envoy Gateway installed
- Gateway API Inference Extension CRDs (v1.0.1)
- InferencePool CRD enabled
- Endpoint Picker Provider (EPP) deployment

### RBAC Permissions
- Access to InferencePool resources
- Access to Pod resources (for endpoint discovery)

## Advanced Features

### Token Rate Limiting
Via `llmRequestCosts` metadata:
- Input tokens
- Output tokens
- Total tokens

### Model Metrics
- Endpoint performance tracking
- Model-specific observability

## Project Integration Notes

### For Self-Hosted Models
InferencePool ideal for:
- vLLM deployments
- Local Ollama instances
- Custom model servers

### Template Considerations
```yaml
# cluster.yaml options
ai_gateway_inference_pool_enabled: false
ai_gateway_self_hosted_models:
  - name: llama3-8b
    pool_name: vllm-llama3-8b-instruct
    port: 8080
```

### Request Timeout
Default 60s - may need adjustment for large model responses.
