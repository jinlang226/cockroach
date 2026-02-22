// Copyright 2026 The Cockroach Authors.
//
// Use of this software is governed by the CockroachDB Software License
// included in the /LICENSE file.

package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	appTraceEnabledEnv     = "COCKROACH_APP_TRACE_ENABLED"
	appTracePathEnv        = "COCKROACH_APP_TRACE_PATH"
	appTraceIDEnv          = "COCKROACH_APP_TRACE_ID"
	appTraceReconcileIDEnv = "COCKROACH_APP_RECONCILE_ID"
)

type appTraceFile struct {
	Events []appTraceEvent `json:"events"`
}

type appTraceEvent struct {
	Timestamp string         `json:"timestamp"`
	EventType string         `json:"eventType"`
	Details   map[string]any `json:"details"`
}

type appTraceSession struct {
	enabled     bool
	path        string
	reconcileID string
	traceID     string
	stepSeq     int
}

var appTraceMu sync.Mutex

func newAppTraceSession(commandName string) appTraceSession {
	enabled := parseTraceBoolEnv(os.Getenv(appTraceEnabledEnv))
	if !enabled {
		return appTraceSession{}
	}

	path := os.Getenv(appTracePathEnv)
	if path == "" {
		path = "./cockroach-app-trace.json"
	}

	now := time.Now().UTC()
	reconcileID := os.Getenv(appTraceReconcileIDEnv)
	if reconcileID == "" {
		reconcileID = fmt.Sprintf("app/%s#%d", commandName, now.UnixNano())
	}
	traceID := os.Getenv(appTraceIDEnv)
	if traceID == "" {
		traceID = fmt.Sprintf("app/%s-%d", commandName, now.UnixNano())
	}

	return appTraceSession{
		enabled:     true,
		path:        path,
		reconcileID: reconcileID,
		traceID:     traceID,
		stepSeq:     1,
	}
}

func (s *appTraceSession) Emit(eventType string, details map[string]any) {
	if s == nil || !s.enabled {
		return
	}
	if details == nil {
		details = map[string]any{}
	}
	if _, ok := details["reconcileId"]; !ok {
		details["reconcileId"] = s.reconcileID
	}
	if _, ok := details["traceId"]; !ok {
		details["traceId"] = s.traceID
	}
	if _, ok := details["stepSeq"]; !ok {
		details["stepSeq"] = s.stepSeq
		s.stepSeq++
	}

	event := appTraceEvent{
		Timestamp: time.Now().UTC().Format(time.RFC3339Nano),
		EventType: eventType,
		Details:   details,
	}
	if err := appendAppTraceEvent(s.path, event); err != nil {
		fmt.Fprintf(stderr, "warning: failed to append app trace event %q: %v\n", eventType, err)
	}
}

func appendAppTraceEvent(path string, event appTraceEvent) error {
	appTraceMu.Lock()
	defer appTraceMu.Unlock()

	traceData := appTraceFile{Events: make([]appTraceEvent, 0, 8)}
	raw, err := os.ReadFile(path)
	if err == nil {
		if len(bytes.TrimSpace(raw)) > 0 {
			if err := json.Unmarshal(raw, &traceData); err != nil {
				return err
			}
		}
	} else if !os.IsNotExist(err) {
		return err
	}

	traceData.Events = append(traceData.Events, event)
	encoded, err := json.MarshalIndent(traceData, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, encoded, 0o644); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}

func parseTraceBoolEnv(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "1", "true", "yes", "on":
		return true
	default:
		return false
	}
}

func classifyNodeInitResult(err error) string {
	if err == nil {
		return "NODE_INIT_OK"
	}
	msg := strings.ToLower(err.Error())
	if strings.Contains(msg, "already initialized") {
		return "NODE_ALREADY_INITIALIZED"
	}
	return "NODE_INIT_ERROR"
}
