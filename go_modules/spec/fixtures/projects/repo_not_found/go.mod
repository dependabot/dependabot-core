module github.com/dependabot/vgotest

go 1.13

require (
	cloud.google.com/go v0.44.0 // indirect
	github.com/emicklei/go-restful v2.9.6+incompatible // indirect
	github.com/go-openapi/spec v0.19.2
	github.com/go-openapi/swag v0.19.4 // indirect
	github.com/gogo/protobuf v1.2.1
	github.com/golang/groupcache v0.0.0-20190702054246-869f871628b6 // indirect
	github.com/golang/protobuf v1.3.2
	github.com/google/uuid v1.1.1 // indirect
	github.com/googleapis/gnostic v0.3.0 // indirect
	github.com/hashicorp/golang-lru v0.5.3 // indirect
	github.com/konsorten/go-windows-terminal-sequences v1.0.2 // indirect
	github.com/kubeflow/common v0.1.0
	github.com/kubeflow/tf-operator v1.0.0-rc.0.0.20190916040037-5adee6f30c86
	github.com/kubernetes-sigs/kube-batch v0.4.2
	github.com/kubernetes-sigs/yaml v1.1.0
	github.com/mailru/easyjson v0.0.0-20190626092158-b2ccc519800e // indirect
	github.com/onrik/logrus v0.4.0
	github.com/prometheus/client_golang v1.1.0
	github.com/sirupsen/logrus v1.4.2
	golang.org/x/crypto v0.0.0-20190701094942-4def268fd1a4 // indirect
	golang.org/x/sys v0.0.0-20190804053845-51ab0e2deafa // indirect
	gopkg.in/square/go-jose.v2 v2.3.1 // indirect
	k8s.io/api v0.15.9
	k8s.io/apimachinery v0.15.9
	k8s.io/client-go v0.15.9
	k8s.io/klog v0.4.0
	k8s.io/kube-openapi v0.0.0-20190228160746-b3a7cee44a30
	k8s.io/kubernetes v1.15.9
	k8s.io/utils v0.0.0-20190809000727-6c36bc71fc4a // indirect
)

replace (
	k8s.io/api => k8s.io/api v0.15.9
	k8s.io/apiextensions-apiserver => k8s.io/apiextensions-apiserver v0.15.9
	k8s.io/apimachinery => k8s.io/apimachinery v0.15.10-beta.0
	k8s.io/apiserver => k8s.io/apiserver v0.15.9
	k8s.io/cli-runtime => k8s.io/cli-runtime v0.15.9
	k8s.io/client-go => k8s.io/client-go v0.15.9
	k8s.io/cloud-provider => k8s.io/cloud-provider v0.15.9
	k8s.io/cluster-bootstrap => k8s.io/cluster-bootstrap v0.15.9
	k8s.io/code-generator => k8s.io/code-generator v0.15.13-beta.0
	k8s.io/component-base => k8s.io/component-base v0.15.9
	k8s.io/cri-api => k8s.io/cri-api v0.15.13-beta.0
	k8s.io/csi-translation-lib => k8s.io/csi-translation-lib v0.15.9
	k8s.io/kube-aggregator => k8s.io/kube-aggregator v0.15.9
	k8s.io/kube-controller-manager => k8s.io/kube-controller-manager v0.15.9
	k8s.io/kube-openapi => k8s.io/kube-openapi v0.0.0-20190228160746-b3a7cee44a30
	k8s.io/kube-proxy => k8s.io/kube-proxy v0.15.9
	k8s.io/kube-scheduler => k8s.io/kube-scheduler v0.15.9
	k8s.io/kubectl => k8s.io/kubectl v0.15.13-beta.0
	k8s.io/kubelet => k8s.io/kubelet v0.15.9
	k8s.io/legacy-cloud-providers => k8s.io/legacy-cloud-providers v0.15.9
	k8s.io/metrics => k8s.io/metrics v0.15.9
	k8s.io/node-api => k8s.io/node-api v0.15.9
	k8s.io/sample-apiserver => k8s.io/sample-apiserver v0.15.9
	k8s.io/sample-cli-plugin => k8s.io/sample-cli-plugin v0.15.9
	k8s.io/sample-controller => k8s.io/sample-controller v0.15.9
)
