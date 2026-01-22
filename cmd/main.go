package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"
)

type EventLoop struct {
	ctx     context.Context
	cancel  context.CancelFunc
	scanner *bufio.Scanner
}

func NewEventLoop() *EventLoop {
	ctx, cancel := context.WithCancel(context.Background())
	return &EventLoop{
		ctx:     ctx,
		cancel:  cancel,
		scanner: bufio.NewScanner(os.Stdin),
	}
}

func (el *EventLoop) Run() error {
	fmt.Println("Ralphussy Terminal - Press Ctrl+C to exit")
	fmt.Println()

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)

	done := make(chan error, 1)

	go func() {
		done <- el.eventLoop()
	}()

	select {
	case err := <-done:
		return err
	case <-sigs:
		fmt.Println("\nReceived interrupt signal, shutting down...")
		el.cancel()
		<-done
		return nil
	}
}

func (el *EventLoop) eventLoop() error {
	for {
		select {
		case <-el.ctx.Done():
			return nil
		default:
			fmt.Print("> ")
			if !el.scanner.Scan() {
				return nil
			}

			input := strings.TrimSpace(el.scanner.Text())
			if input == "" {
				continue
			}

			if err := el.processCommand(input); err != nil {
				fmt.Printf("Error: %v\n", err)
			}
		}
	}
}

func (el *EventLoop) processCommand(input string) error {
	parts := strings.Fields(input)
	if len(parts) == 0 {
		return nil
	}

	cmd := parts[0]
	args := parts[1:]

	switch cmd {
	case "exit", "quit":
		el.cancel()
		return nil
	case "help":
		el.showHelp()
	case "echo":
		fmt.Println(strings.Join(args, " "))
	default:
		fmt.Printf("Unknown command: %s\n", cmd)
		fmt.Println("Type 'help' for available commands")
	}

	return nil
}

func (el *EventLoop) showHelp() {
	fmt.Println("Available commands:")
	fmt.Println("  help    - Show this help message")
	fmt.Println("  echo    - Echo back the provided text")
	fmt.Println("  exit    - Exit the terminal")
	fmt.Println("  quit    - Exit the terminal")
}

func (el *EventLoop) Stop() {
	el.cancel()
}

func main() {
	loop := NewEventLoop()
	if err := loop.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
