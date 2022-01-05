// Copyright 2018 Telefónica
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"github.com/confluentinc/confluent-kafka-go/kafka"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/sirupsen/logrus"
)

var (
	httpRequestsTotal = prometheus.NewCounter(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Count of all http requests",
		})
	queueSizeDesc = prometheus.NewDesc(
		"kafka_queue_size",
		"Queue size for metrics sent to Kafka",
		[]string{},
		prometheus.Labels{},
	)
)

type queueLenCollector struct {
	producer *kafka.Producer
}

func (queueLenCollector) Describe(descChan chan<- *prometheus.Desc) {
	descChan <- queueSizeDesc
}

func (qlc queueLenCollector) Collect(metricChan chan<- prometheus.Metric) {
	qLen := float64(qlc.producer.Len())
	met, err := prometheus.NewConstMetric(queueSizeDesc, prometheus.GaugeValue, qLen)
	if err != nil {
		logrus.WithError(err).Error("Error collecting kafka_queue_size metric")
	}
	metricChan <- met
}

func initMetrics(producer *kafka.Producer) {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(&queueLenCollector{producer: producer})
}
