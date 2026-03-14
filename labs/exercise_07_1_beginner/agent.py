"""AgentForge Exercise 07.1 — Infrastructure & Orchestration Agents (beginner)"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from core.agent_base import AgentBase

def main():
    agent = AgentBase(name="ex-07-1", instruction="You are a Infrastructure & Orchestration Agents agent.")
    print(f"Exercise 07.1 ready: {agent.name}")

if __name__ == "__main__":
    main()
